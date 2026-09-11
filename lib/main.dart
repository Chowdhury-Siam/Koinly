import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:awesome_snackbar_content/awesome_snackbar_content.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';
import 'package:lottie/lottie.dart';
import 'package:timelines_plus/timelines_plus.dart';
import 'package:flutter/foundation.dart' hide Category, Summary;
import 'package:flutter/material.dart' hide Category, Summary;
import 'package:flutter/cupertino.dart' hide Category, Summary;
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:sqflite/sqflite.dart' as sql;
import 'package:sqflite_common_ffi/sqflite_ffi.dart' as sqflite_ffi;
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';
import 'package:video_player/video_player.dart';

import 'android_saf_backup_store.dart';
import 'app_config.dart';
import 'branding_widgets.dart';
import 'category_deduplication.dart';
import 'collection_utils.dart';
import 'data_merge.dart';
import 'icon_helpers.dart';
import 'models.dart';
import 'loans/loan_computation.dart';
import 'loans/loan_models.dart';
import 'loans/loan_repository.dart';
import 'persistence_stores.dart';
import 'profile/profile_media.dart';
import 'reminder_service.dart';
import 'sync_models.dart';
import 'sync_services.dart';
import 'ui_foundation.dart';
import 'update_service.dart';
import 'update_background_service.dart';

part 'loans/loan_controller_part.dart';
part 'loans/loan_screens.dart';
part 'loans/loan_sheets.dart';
part 'profile/profile_ui.dart';

const _uuid = Uuid();

String? _syncUsernameValidationError(String value) {
  final username = value.trim().toLowerCase();
  if (!RegExp(r'^[a-z0-9](?:[a-z0-9._-]{1,30}[a-z0-9])?$').hasMatch(username)) {
    return 'Username must be 3-32 characters using letters, numbers, dots, dashes, or underscores.';
  }
  return null;
}

String _legacyUsernameFromEmail(String value) {
  final raw = value.trim().toLowerCase();
  if (raw.isEmpty) return '';
  final local = raw.contains('@') ? raw.split('@').first : raw;
  var username = local.replaceAll(RegExp(r'[^a-z0-9._-]+'), '_');
  username = username.replaceAll(RegExp(r'^[._-]+|[._-]+$'), '');
  if (username.isEmpty) username = 'koinly_owner';
  while (username.length < 3) { username = '${username}_owner'; }
  if (username.length > 32) username = username.substring(0, 32);
  username = username.replaceAll(RegExp(r'[._-]+$'), '');
  return username.isEmpty ? 'koinly_owner' : username;
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (kUsesDesktopSqlite) {
    sqflite_ffi.sqfliteFfiInit();
    sql.databaseFactory = sqflite_ffi.databaseFactoryFfi;
  }
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    systemNavigationBarColor: Colors.transparent,
  ));

  try {
    await Firebase.initializeApp();
    FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;
    PlatformDispatcher.instance.onError = (error, stack) {
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
      return true;
    };
  } catch (_) {
    // Firebase remains optional for local builds without a generated FlutterFire options file.
  }

  await ReminderService.ensureInitialized();
  await UpdateBackgroundService.initialize();

  runApp(
    ChangeNotifierProvider(
      create: (_) => AppController()..initialize(),
      child: const KoinlyApp(),
    ),
  );
}

// -----------------------------------------------------------------------------
// Database and persistence
// -----------------------------------------------------------------------------

class BudgetCategoryReferenceMerge {
  const BudgetCategoryReferenceMerge({
    required this.budgetId,
    required this.duplicateCategoryId,
    required this.canonicalCategoryId,
  });

  final String budgetId;
  final String duplicateCategoryId;
  final String canonicalCategoryId;
}

class CategoryDatabaseMergeResult {
  const CategoryDatabaseMergeResult({
    required this.plan,
    required this.updatedTransactionIds,
    required this.updatedPlannedPurchaseIds,
    required this.updatedBudgetReferences,
  });

  static const empty = CategoryDatabaseMergeResult(
    plan: CategoryMergePlan.empty,
    updatedTransactionIds: <String>{},
    updatedPlannedPurchaseIds: <String>{},
    updatedBudgetReferences: <BudgetCategoryReferenceMerge>[],
  );

  final CategoryMergePlan plan;
  final Set<String> updatedTransactionIds;
  final Set<String> updatedPlannedPurchaseIds;
  final List<BudgetCategoryReferenceMerge> updatedBudgetReferences;

  bool get hasChanges => plan.hasChanges;
}

class KoinlyDatabase {
  sql.Database? _db;

  Future<sql.Database> get db async {
    if (_db != null) return _db!;
    final dir = await sql.getDatabasesPath();
    final path = p.join(dir, 'koinly_flutter.db');
    _db = await sql.openDatabase(
      path,
      version: 10,
      onCreate: (database, version) async {
        await _createSchema(database);
        await _seed(database);
      },
      onUpgrade: (database, oldVersion, newVersion) async {
        await _createSchema(database);
        await _ensureTransactionMetadataColumns(database);
      },
      onOpen: (database) async {
        await _createSchema(database);
        await _ensureTransactionMetadataColumns(database);
      },
    );
    return _db!;
  }

  Future<void> _createSchema(sql.Database database) async {
    await database.execute('''
      CREATE TABLE IF NOT EXISTS accounts(
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        type TEXT NOT NULL,
        icon_name TEXT NOT NULL,
        icon_color TEXT NOT NULL,
        amount REAL NOT NULL DEFAULT 0,
        credit_limit REAL NOT NULL DEFAULT 0,
        sequence INTEGER NOT NULL DEFAULT 0,
        created_on INTEGER NOT NULL,
        updated_on INTEGER NOT NULL
      )
    ''');
    await database.execute('''
      CREATE TABLE IF NOT EXISTS categories(
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        type TEXT NOT NULL,
        icon_name TEXT NOT NULL,
        icon_color TEXT NOT NULL,
        created_on INTEGER NOT NULL,
        updated_on INTEGER NOT NULL
      )
    ''');
    await database.execute('''
      CREATE TABLE IF NOT EXISTS planned_purchases(
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        amount REAL NOT NULL,
        category_id TEXT NOT NULL,
        created_on INTEGER NOT NULL,
        updated_on INTEGER NOT NULL
      )
    ''');
    await database.execute('''
      CREATE TABLE IF NOT EXISTS transactions(
        id TEXT PRIMARY KEY,
        type TEXT NOT NULL,
        amount REAL NOT NULL,
        title TEXT NOT NULL DEFAULT '',
        notes TEXT NOT NULL,
        category_id TEXT NOT NULL,
        from_account_id TEXT NOT NULL,
        to_account_id TEXT,
        image_path TEXT NOT NULL DEFAULT '',
        exclude_from_reports INTEGER NOT NULL DEFAULT 0,
        linked_entity_type TEXT,
        linked_entity_id TEXT,
        created_on INTEGER NOT NULL,
        end_on INTEGER,
        updated_on INTEGER NOT NULL
      )
    ''');
    // Existing databases can reach this method before onUpgrade's follow-up
    // migration runs. Add the columns before creating their index below.
    await _ensureTransactionMetadataColumns(database);
    await database.execute('''
      CREATE TABLE IF NOT EXISTS budgets(
        id TEXT PRIMARY KEY,
        selected_month TEXT NOT NULL,
        amount REAL NOT NULL,
        all_accounts_selected INTEGER NOT NULL DEFAULT 1,
        all_categories_selected INTEGER NOT NULL DEFAULT 1,
        created_on INTEGER NOT NULL,
        updated_on INTEGER NOT NULL
      )
    ''');
    await database.execute('''
      CREATE TABLE IF NOT EXISTS budget_accounts(
        budget_id TEXT NOT NULL,
        account_id TEXT NOT NULL,
        PRIMARY KEY(budget_id, account_id)
      )
    ''');
    await database.execute('''
      CREATE TABLE IF NOT EXISTS budget_categories(
        budget_id TEXT NOT NULL,
        category_id TEXT NOT NULL,
        PRIMARY KEY(budget_id, category_id)
      )
    ''');
    await database.execute('''
      CREATE TABLE IF NOT EXISTS loan_contacts(
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        phone TEXT NOT NULL DEFAULT '',
        note TEXT NOT NULL DEFAULT '',
        icon_name TEXT NOT NULL DEFAULT 'exchange',
        icon_color TEXT NOT NULL DEFAULT '#FBC879',
        archived INTEGER NOT NULL DEFAULT 0,
        created_on INTEGER NOT NULL,
        updated_on INTEGER NOT NULL
      )
    ''');
    await database.execute('''
      CREATE TABLE IF NOT EXISTS loans(
        id TEXT PRIMARY KEY,
        contact_id TEXT NOT NULL,
        direction TEXT NOT NULL,
        principal REAL NOT NULL,
        interest_type TEXT NOT NULL DEFAULT 'none',
        interest_rate REAL NOT NULL DEFAULT 0,
        interest_period TEXT NOT NULL DEFAULT 'yearly',
        start_date INTEGER NOT NULL,
        due_date INTEGER,
        installment_count INTEGER,
        interest_accrual_stop TEXT NOT NULL DEFAULT 'settled',
        note TEXT NOT NULL DEFAULT '',
        status TEXT NOT NULL DEFAULT 'active',
        closed_on INTEGER,
        disbursal_transaction_id TEXT,
        created_on INTEGER NOT NULL,
        updated_on INTEGER NOT NULL
      )
    ''');
    await database.execute('''
      CREATE TABLE IF NOT EXISTS loan_payments(
        id TEXT PRIMARY KEY,
        loan_id TEXT NOT NULL,
        amount REAL NOT NULL,
        interest_component REAL NOT NULL DEFAULT 0,
        principal_component REAL NOT NULL DEFAULT 0,
        paid_on INTEGER NOT NULL,
        note TEXT NOT NULL DEFAULT '',
        transaction_id TEXT,
        created_on INTEGER NOT NULL,
        updated_on INTEGER NOT NULL
      )
    ''');
    await database.execute('''
      CREATE TABLE IF NOT EXISTS sync_state(
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');
    await database.execute('''
      CREATE TABLE IF NOT EXISTS sync_outbox(
        id TEXT PRIMARY KEY,
        entity_type TEXT NOT NULL,
        entity_id TEXT NOT NULL,
        operation TEXT NOT NULL,
        payload_json TEXT,
        base_version INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL,
        attempt_count INTEGER NOT NULL DEFAULT 0,
        last_attempt_at INTEGER,
        last_error TEXT
      )
    ''');
    await database.execute('''
      CREATE TABLE IF NOT EXISTS sync_entity_versions(
        entity_type TEXT NOT NULL,
        entity_id TEXT NOT NULL,
        version INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY(entity_type, entity_id)
      )
    ''');
    await database.execute('''
      CREATE TABLE IF NOT EXISTS sync_conflicts(
        id TEXT PRIMARY KEY,
        entity_type TEXT NOT NULL,
        entity_id TEXT NOT NULL,
        local_operation_id TEXT,
        server_version INTEGER NOT NULL DEFAULT 0,
        details TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        resolved_at INTEGER
      )
    ''');
    await database.execute('CREATE INDEX IF NOT EXISTS idx_sync_outbox_created ON sync_outbox(created_at)');
    await database.execute('CREATE INDEX IF NOT EXISTS idx_sync_outbox_entity ON sync_outbox(entity_type, entity_id)');
    await database.execute('CREATE INDEX IF NOT EXISTS idx_sync_conflicts_open ON sync_conflicts(resolved_at, created_at)');
    await database.execute('CREATE INDEX IF NOT EXISTS idx_loans_contact ON loans(contact_id)');
    await database.execute('CREATE INDEX IF NOT EXISTS idx_loans_status_due ON loans(status, due_date)');
    await database.execute('CREATE INDEX IF NOT EXISTS idx_loan_payments_loan ON loan_payments(loan_id, paid_on)');
    await database.execute('CREATE INDEX IF NOT EXISTS idx_loan_contacts_name ON loan_contacts(name COLLATE NOCASE)');
    await database.execute('CREATE INDEX IF NOT EXISTS idx_transactions_linked_entity ON transactions(linked_entity_type, linked_entity_id)');
  }

  Future<void> _ensureTransactionMetadataColumns(sql.Database database) async {
    final columns = (await database.rawQuery('PRAGMA table_info(transactions)'))
        .map((row) => row['name']?.toString() ?? '')
        .toSet();
    if (!columns.contains('exclude_from_reports')) {
      await database.execute('ALTER TABLE transactions ADD COLUMN exclude_from_reports INTEGER NOT NULL DEFAULT 0');
    }
    if (!columns.contains('title')) {
      await database.execute("ALTER TABLE transactions ADD COLUMN title TEXT NOT NULL DEFAULT ''");
    }
    await database.rawUpdate('''
      UPDATE transactions
      SET title = COALESCE(
        (SELECT name FROM categories WHERE categories.id = transactions.category_id),
        CASE type WHEN 'income' THEN 'Income' ELSE 'Expense' END
      )
      WHERE type IN ('income', 'expense') AND TRIM(title) = ''
    ''');
    if (!columns.contains('linked_entity_type')) {
      await database.execute('ALTER TABLE transactions ADD COLUMN linked_entity_type TEXT');
    }
    if (!columns.contains('linked_entity_id')) {
      await database.execute('ALTER TABLE transactions ADD COLUMN linked_entity_id TEXT');
    }
    if (!columns.contains('end_on')) {
      await database.execute('ALTER TABLE transactions ADD COLUMN end_on INTEGER');
    }
  }

  Future<void> _seed(sql.Database database) async {
    // Starter accounts are intentionally NOT inserted when the database is
    // created. They are created only after the user explicitly chooses
    // "Start new" during onboarding. This prevents Login/Restore flows from
    // ever inheriting placeholder Cash/Card/Bank Account rows.
    final categoryCount = sql.Sqflite.firstIntValue(await database.rawQuery('SELECT COUNT(*) FROM categories')) ?? 0;
    if (categoryCount > 0) return;
    final now = DateTime.now();

    final expense = [
      ['Clothing', 'apparel', '#F5A3A3'],
      ['Entertainment', 'games', '#B5A7FF'],
      ['Food', 'food', '#FBC879'],
      ['Health', 'health', '#98E2C6'],
      ['Leisure', 'leisure', '#A7D0FF'],
      ['Shopping', 'cart', '#FFB5D0'],
      ['Transportation', 'car', '#AEE9F1'],
      ['Utilities', 'bolt', '#CCD6A6'],
    ];
    final income = [
      ['Salary', 'salary', '#A6E3A1'],
      ['Gift', 'gift', '#FFDE7D'],
      ['Coupons', 'coupon', '#B4A5FF'],
    ];
    for (final data in expense) {
      await database.insert('categories', Category(id: _uuid.v4(), name: data[0], type: CategoryType.expense, iconName: data[1], iconColor: data[2], createdOn: now, updatedOn: now).toMap());
    }
    for (final data in income) {
      await database.insert('categories', Category(id: _uuid.v4(), name: data[0], type: CategoryType.income, iconName: data[1], iconColor: data[2], createdOn: now, updatedOn: now).toMap());
    }
  }

  Future<List<Account>> accounts() async {
    final maps = await (await db).query('accounts', orderBy: 'sequence ASC, created_on ASC');
    return maps.map(Account.fromMap).toList();
  }

  Future<List<String>> ensureStarterAccountsForNewSetup() async {
    final database = await db;
    final existing = await database.query('accounts', columns: ['id']);
    if (existing.isNotEmpty) return const <String>[];

    final now = DateTime.now();
    final starterAccounts = [
      Account(id: _uuid.v4(), name: 'Cash', type: AccountType.regular, iconName: 'wallet', iconColor: kSleekAccentHex, amount: 0, creditLimit: 0, sequence: 0, createdOn: now, updatedOn: now),
      Account(id: _uuid.v4(), name: 'Card', type: AccountType.credit, iconName: 'credit_card', iconColor: '#89A7FF', amount: 0, creditLimit: 0, sequence: 1, createdOn: now, updatedOn: now),
      Account(id: _uuid.v4(), name: 'Bank Account', type: AccountType.regular, iconName: 'bank', iconColor: '#A6E3A1', amount: 0, creditLimit: 0, sequence: 2, createdOn: now, updatedOn: now),
    ];
    for (final account in starterAccounts) {
      await database.insert('accounts', account.toMap());
    }
    return starterAccounts.map((account) => account.id).toList(growable: false);
  }

  Future<List<String>> deletePreloadedStarterAccountsForImport() async {
    final database = await db;
    final rows = await database.query('accounts');
    final deletedIds = <String>[];

    bool isPreloadedFingerprint(Account account) {
      if (account.amount != 0 || account.creditLimit != 0) return false;
      return (account.name == 'Cash' &&
              account.type == AccountType.regular &&
              account.iconName == 'wallet' &&
              {kLegacyStarterCashIconHex, kSleekAccentHex}.contains(account.iconColor.toUpperCase())) ||
          (account.name == 'Card' &&
              account.type == AccountType.credit &&
              account.iconName == 'credit_card' &&
              account.iconColor.toUpperCase() == '#89A7FF') ||
          (account.name == 'Bank Account' &&
              account.type == AccountType.regular &&
              account.iconName == 'bank' &&
              account.iconColor.toUpperCase() == '#A6E3A1');
    }

    await database.transaction((txn) async {
      for (final row in rows) {
        final account = Account.fromMap(row);
        if (!isPreloadedFingerprint(account)) continue;
        final transactionReferences = sql.Sqflite.firstIntValue(await txn.rawQuery(
              '''
              SELECT COUNT(*) FROM transactions
              WHERE from_account_id = ? OR to_account_id = ?
              ''',
              [account.id, account.id],
            )) ??
            0;
        final budgetReferences = sql.Sqflite.firstIntValue(await txn.rawQuery(
              'SELECT COUNT(*) FROM budget_accounts WHERE account_id = ?',
              [account.id],
            )) ??
            0;
        if (transactionReferences == 0 && budgetReferences == 0) {
          await txn.delete('accounts', where: 'id = ?', whereArgs: [account.id]);
          deletedIds.add(account.id);
        }
      }
    });
    return deletedIds;
  }

  Future<bool> hasRedundantPreloadedStarterAccountEvidence() async {
    final database = await db;
    final rows = await database.query('accounts');
    if (rows.length < 2) return false;
    final parsed = rows.map(Account.fromMap).toList(growable: false);
    final nameCounts = <String, int>{};
    for (final account in parsed) {
      final key = account.name.trim().toLowerCase();
      nameCounts[key] = (nameCounts[key] ?? 0) + 1;
    }

    bool isPreloadedFingerprint(Account account) {
      if (account.amount != 0 || account.creditLimit != 0) return false;
      return (account.name == 'Cash' &&
              account.type == AccountType.regular &&
              account.iconName == 'wallet' &&
              {kLegacyStarterCashIconHex, kSleekAccentHex}.contains(account.iconColor.toUpperCase())) ||
          (account.name == 'Card' &&
              account.type == AccountType.credit &&
              account.iconName == 'credit_card' &&
              account.iconColor.toUpperCase() == '#89A7FF') ||
          (account.name == 'Bank Account' &&
              account.type == AccountType.regular &&
              account.iconName == 'bank' &&
              account.iconColor.toUpperCase() == '#A6E3A1');
    }

    for (final account in parsed) {
      if (!isPreloadedFingerprint(account)) continue;
      if ((nameCounts[account.name.trim().toLowerCase()] ?? 0) < 2) continue;
      final transactionReferences = sql.Sqflite.firstIntValue(await database.rawQuery(
            '''
            SELECT COUNT(*) FROM transactions
            WHERE from_account_id = ? OR to_account_id = ?
            ''',
            [account.id, account.id],
          )) ??
          0;
      final budgetReferences = sql.Sqflite.firstIntValue(await database.rawQuery(
            'SELECT COUNT(*) FROM budget_accounts WHERE account_id = ?',
            [account.id],
          )) ??
          0;
      if (transactionReferences == 0 && budgetReferences == 0) return true;
    }
    return false;
  }

  Future<void> upsertAccount(Account account) async => (await db).insert('accounts', account.toMap(), conflictAlgorithm: sql.ConflictAlgorithm.replace);

  Future<void> deleteAccount(String id) async => (await db).delete('accounts', where: 'id = ?', whereArgs: [id]);

  Future<List<String>> deleteUntouchedStarterAccounts() async {
    final database = await db;
    final starterNames = const {'Cash', 'Card', 'Bank Account'};
    final rows = await database.query('accounts');
    final deletedIds = <String>[];
    await database.transaction((txn) async {
      for (final row in rows) {
        final account = Account.fromMap(row);
        if (!starterNames.contains(account.name) || account.amount != 0 || account.creditLimit != 0) continue;
        final transactionReferences = sql.Sqflite.firstIntValue(await txn.rawQuery(
              '''
              SELECT COUNT(*) FROM transactions
              WHERE from_account_id = ? OR to_account_id = ?
              ''',
              [account.id, account.id],
            )) ??
            0;
        final budgetReferences = sql.Sqflite.firstIntValue(await txn.rawQuery(
              'SELECT COUNT(*) FROM budget_accounts WHERE account_id = ?',
              [account.id],
            )) ??
            0;
        if (transactionReferences == 0 && budgetReferences == 0) {
          await txn.delete('accounts', where: 'id = ?', whereArgs: [account.id]);
          deletedIds.add(account.id);
        }
      }
    });
    return deletedIds;
  }

  Future<bool> hasOnlyUntouchedStarterAccounts() async {
    final database = await db;
    final starterNames = const {'Cash', 'Card', 'Bank Account'};
    final rows = await database.query('accounts');
    if (rows.length != starterNames.length) return false;

    final accountNames = <String>{};
    for (final row in rows) {
      final account = Account.fromMap(row);
      if (!starterNames.contains(account.name) || account.amount != 0 || account.creditLimit != 0) return false;
      accountNames.add(account.name);
    }
    if (accountNames.length != rows.length) return false;
    if (!accountNames.containsAll(starterNames)) return false;

    final userActivityCount = sql.Sqflite.firstIntValue(await database.rawQuery(
          '''
          SELECT
            (SELECT COUNT(*) FROM transactions) +
            (SELECT COUNT(*) FROM budgets) +
            (SELECT COUNT(*) FROM budget_accounts) +
            (SELECT COUNT(*) FROM loans)
          ''',
        )) ??
        0;
    return userActivityCount == 0;
  }

  Future<void> reorderAccounts(List<Account> ordered) async {
    final database = await db;
    await database.transaction((txn) async {
      for (var i = 0; i < ordered.length; i++) {
        await txn.update('accounts', {'sequence': i, 'updated_on': dateToDb(DateTime.now())}, where: 'id = ?', whereArgs: [ordered[i].id]);
      }
    });
  }

  Future<List<Category>> categories() async {
    final maps = await (await db).query('categories', orderBy: 'type ASC, name COLLATE NOCASE ASC');
    return maps.map(Category.fromMap).toList();
  }

  Future<void> upsertCategory(Category category) async {
    final database = await db;
    final normalizedName = normalizeCategoryDisplayName(category.name);
    if (normalizedName.isEmpty) throw StateError('Enter a category name.');
    final identity = categoryIdentityKey(enumName(category.type), normalizedName);
    final sameTypeRows = await database.query('categories', where: 'type = ?', whereArgs: [enumName(category.type)]);
    for (final row in sameTypeRows) {
      final existingId = row['id']?.toString() ?? '';
      if (existingId != category.id && categoryIdentityKey(row['type']?.toString() ?? '', row['name']?.toString() ?? '') == identity) {
        throw StateError('A ${enumName(category.type)} category named "$normalizedName" already exists.');
      }
    }
    await database.insert(
      'categories',
      category.copyWith(name: normalizedName).toMap(),
      conflictAlgorithm: sql.ConflictAlgorithm.replace,
    );
  }
  Future<void> deleteCategory(String id) async => (await db).delete('categories', where: 'id = ?', whereArgs: [id]);

  Future<CategoryDatabaseMergeResult> mergeDuplicateCategories() async {
    final database = await db;
    final rows = await database.query('categories');
    final plan = buildCategoryMergePlan(rows);
    if (!plan.hasChanges) return CategoryDatabaseMergeResult.empty;

    final updatedTransactionIds = <String>{};
    final updatedPlannedPurchaseIds = <String>{};
    final updatedBudgetReferences = <BudgetCategoryReferenceMerge>[];
    final budgetReferenceKeys = <String>{};
    await database.transaction((txn) async {
      final now = dateToDb(DateTime.now());
      for (final entry in plan.normalizedNamesByCanonicalId.entries) {
        await txn.update(
          'categories',
          {'name': entry.value, 'updated_on': now},
          where: 'id = ?',
          whereArgs: [entry.key],
        );
      }
      for (final entry in plan.duplicateToCanonicalId.entries) {
        final duplicateId = entry.key;
        final canonicalId = entry.value;
        final transactionRows = await txn.query('transactions', columns: ['id'], where: 'category_id = ?', whereArgs: [duplicateId]);
        updatedTransactionIds.addAll(transactionRows.map((row) => row['id']?.toString() ?? '').where((id) => id.isNotEmpty));
        await txn.update('transactions', {'category_id': canonicalId}, where: 'category_id = ?', whereArgs: [duplicateId]);

        final plannedRows = await txn.query('planned_purchases', columns: ['id'], where: 'category_id = ?', whereArgs: [duplicateId]);
        updatedPlannedPurchaseIds.addAll(plannedRows.map((row) => row['id']?.toString() ?? '').where((id) => id.isNotEmpty));
        await txn.update('planned_purchases', {'category_id': canonicalId, 'updated_on': now}, where: 'category_id = ?', whereArgs: [duplicateId]);

        final budgetRows = await txn.query('budget_categories', columns: ['budget_id'], where: 'category_id = ?', whereArgs: [duplicateId]);
        for (final row in budgetRows) {
          final budgetId = row['budget_id']?.toString() ?? '';
          if (budgetId.isEmpty) continue;
          await txn.insert(
            'budget_categories',
            {'budget_id': budgetId, 'category_id': canonicalId},
            conflictAlgorithm: sql.ConflictAlgorithm.ignore,
          );
          final key = '$budgetId\u0000$duplicateId\u0000$canonicalId';
          if (budgetReferenceKeys.add(key)) {
            updatedBudgetReferences.add(BudgetCategoryReferenceMerge(
              budgetId: budgetId,
              duplicateCategoryId: duplicateId,
              canonicalCategoryId: canonicalId,
            ));
          }
        }
        await txn.delete('budget_categories', where: 'category_id = ?', whereArgs: [duplicateId]);
        await txn.delete('categories', where: 'id = ?', whereArgs: [duplicateId]);
      }
    });

    return CategoryDatabaseMergeResult(
      plan: plan,
      updatedTransactionIds: Set.unmodifiable(updatedTransactionIds),
      updatedPlannedPurchaseIds: Set.unmodifiable(updatedPlannedPurchaseIds),
      updatedBudgetReferences: List.unmodifiable(updatedBudgetReferences),
    );
  }

  Future<List<PlannedPurchase>> plannedPurchases() async {
    final maps = await (await db).query(
      'planned_purchases',
      orderBy: 'updated_on DESC, created_on DESC',
    );
    return maps.map(PlannedPurchase.fromMap).toList();
  }

  Future<void> upsertPlannedPurchase(PlannedPurchase item) async {
    await (await db).insert(
      'planned_purchases',
      item.toMap(),
      conflictAlgorithm: sql.ConflictAlgorithm.replace,
    );
  }

  Future<void> deletePlannedPurchase(String id) async {
    await (await db).delete('planned_purchases', where: 'id = ?', whereArgs: [id]);
  }

  Future<MoneyTransaction> purchasePlannedItem(
    PlannedPurchase item,
    String accountId,
  ) async {
    final database = await db;
    final now = DateTime.now();
    final transaction = MoneyTransaction(
      id: _uuid.v4(),
      type: MoneyTransactionType.expense,
      amount: item.amount,
      title: item.name,
      notes: '',
      categoryId: item.categoryId,
      fromAccountId: accountId,
      linkedEntityType: 'purchase_plan',
      linkedEntityId: item.id,
      createdOn: now,
      updatedOn: now,
    );

    await database.transaction((txn) async {
      final accountRows = await txn.query('accounts', columns: ['id'], where: 'id = ?', whereArgs: [accountId], limit: 1);
      if (accountRows.isEmpty) throw StateError('Selected account no longer exists.');
      final categoryRows = await txn.query('categories', columns: ['id', 'type'], where: 'id = ?', whereArgs: [item.categoryId], limit: 1);
      if (categoryRows.isEmpty || categoryRows.first['type'] != enumName(CategoryType.expense)) {
        throw StateError('Selected expense category no longer exists.');
      }
      final planRows = await txn.query('planned_purchases', columns: ['id'], where: 'id = ?', whereArgs: [item.id], limit: 1);
      if (planRows.isEmpty) throw StateError('This planned item no longer exists.');

      await txn.insert('transactions', transaction.toMap(), conflictAlgorithm: sql.ConflictAlgorithm.abort);
      await _applyTransaction(txn, transaction, 1);
      await txn.delete('planned_purchases', where: 'id = ?', whereArgs: [item.id]);
    });

    return transaction;
  }

  Future<List<MoneyTransaction>> transactions() async {
    final maps = await (await db).query(
      'transactions',
      orderBy: 'CASE WHEN end_on IS NOT NULL AND end_on >= created_on THEN end_on ELSE created_on END DESC, created_on DESC, updated_on DESC',
    );
    return maps.map(MoneyTransaction.fromMap).toList();
  }

  Future<void> addTransaction(MoneyTransaction transaction) async {
    if (transaction.type == MoneyTransactionType.transfer && transaction.fromAccountId == transaction.toAccountId) {
      throw StateError('Transfer source and destination account cannot be the same.');
    }
    final database = await db;
    await database.transaction((txn) async {
      await txn.insert('transactions', transaction.toMap(), conflictAlgorithm: sql.ConflictAlgorithm.replace);
      await _applyTransaction(txn, transaction, 1);
    });
  }

  Future<void> updateTransaction(MoneyTransaction updated) async {
    final database = await db;
    final oldRows = await database.query('transactions', where: 'id = ?', whereArgs: [updated.id], limit: 1);
    if (oldRows.isEmpty) {
      await addTransaction(updated);
      return;
    }
    final old = MoneyTransaction.fromMap(oldRows.first);
    await database.transaction((txn) async {
      await _applyTransaction(txn, old, -1);
      await txn.update('transactions', updated.toMap(), where: 'id = ?', whereArgs: [updated.id]);
      await _applyTransaction(txn, updated, 1);
    });
  }

  Future<void> deleteTransaction(String id) async {
    final database = await db;
    final oldRows = await database.query('transactions', where: 'id = ?', whereArgs: [id], limit: 1);
    if (oldRows.isEmpty) return;
    final old = MoneyTransaction.fromMap(oldRows.first);
    await database.transaction((txn) async {
      await _applyTransaction(txn, old, -1);
      await txn.delete('transactions', where: 'id = ?', whereArgs: [id]);
    });
  }

  Future<void> _applyTransaction(sql.Transaction txn, MoneyTransaction tx, int direction) async {
    Future<void> updateAmount(String accountId, double delta) async {
      if (accountId.isEmpty) return;
      await txn.rawUpdate('UPDATE accounts SET amount = amount + ?, updated_on = ? WHERE id = ?', [delta * direction, dateToDb(DateTime.now()), accountId]);
    }

    if (tx.type == MoneyTransactionType.income) {
      await updateAmount(tx.fromAccountId, tx.amount);
    } else if (tx.type == MoneyTransactionType.expense) {
      await updateAmount(tx.fromAccountId, -tx.amount);
    } else {
      await updateAmount(tx.fromAccountId, -tx.amount);
      await updateAmount(tx.toAccountId ?? '', tx.amount);
    }
  }

  Future<Category> ensureCategory(String name, CategoryType type, String color, String icon) async {
    final database = await db;
    final normalizedName = normalizeCategoryDisplayName(name);
    final identity = categoryIdentityKey(enumName(type), normalizedName);
    final rows = await database.query('categories', where: 'type = ?', whereArgs: [enumName(type)]);
    for (final row in rows) {
      if (categoryIdentityKey(row['type']?.toString() ?? '', row['name']?.toString() ?? '') == identity) {
        return Category.fromMap(row);
      }
    }
    final now = DateTime.now();
    final category = Category(id: _uuid.v4(), name: normalizedName, type: type, iconName: icon, iconColor: color, createdOn: now, updatedOn: now);
    await database.insert('categories', category.toMap());
    return category;
  }

  Future<List<Budget>> budgets() async {
    final database = await db;
    final rows = await database.query('budgets', orderBy: 'selected_month DESC');
    final result = <Budget>[];
    for (final row in rows) {
      final id = row['id'] as String;
      final accountIds = (await database.query('budget_accounts', columns: ['account_id'], where: 'budget_id = ?', whereArgs: [id])).map((e) => e['account_id'] as String).toList();
      final categoryIds = (await database.query('budget_categories', columns: ['category_id'], where: 'budget_id = ?', whereArgs: [id])).map((e) => e['category_id'] as String).toList();
      result.add(Budget.fromMap(row, accountIds, categoryIds));
    }
    return result;
  }

  Future<void> upsertBudget(Budget budget) async {
    final database = await db;
    await database.transaction((txn) async {
      await txn.insert('budgets', budget.toMap(), conflictAlgorithm: sql.ConflictAlgorithm.replace);
      await txn.delete('budget_accounts', where: 'budget_id = ?', whereArgs: [budget.id]);
      await txn.delete('budget_categories', where: 'budget_id = ?', whereArgs: [budget.id]);
      for (final accountId in budget.accountIds) {
        await txn.insert('budget_accounts', {'budget_id': budget.id, 'account_id': accountId});
      }
      for (final categoryId in budget.categoryIds) {
        await txn.insert('budget_categories', {'budget_id': budget.id, 'category_id': categoryId});
      }
    });
  }

  Future<void> deleteBudget(String id) async {
    final database = await db;
    await database.transaction((txn) async {
      await txn.delete('budget_accounts', where: 'budget_id = ?', whereArgs: [id]);
      await txn.delete('budget_categories', where: 'budget_id = ?', whereArgs: [id]);
      await txn.delete('budgets', where: 'id = ?', whereArgs: [id]);
    });
  }


  Future<Map<String, dynamic>> exportAll() async {
    final database = await db;
    final tables = ['accounts', 'categories', 'planned_purchases', 'transactions', 'budgets', 'budget_accounts', 'budget_categories', 'loan_contacts', 'loans', 'loan_payments'];
    final data = <String, dynamic>{};
    for (final table in tables) {
      data[table] = await database.query(table);
    }
    return data;
  }

  Future<CategoryMergePlan> importAll(Map<String, dynamic> data) async {
    final database = await db;
    final normalized = normalizeCategoryDatabasePayload(data);
    final tables = ['loan_payments', 'loans', 'loan_contacts', 'budget_categories', 'budget_accounts', 'budgets', 'transactions', 'planned_purchases', 'categories', 'accounts'];
    await database.transaction((txn) async {
      for (final table in tables) {
        await txn.delete(table);
      }
      for (final table in tables.reversed) {
        final rows = (normalized.database[table] as List? ?? []).cast<Map>();
        for (final row in rows) {
          final rowMap = Map<String, Object?>.from(row);
          await txn.insert(table, rowMap, conflictAlgorithm: sql.ConflictAlgorithm.replace);
        }
      }
    });
    return normalized.plan;
  }

  Future<CategoryMergePlan> mergeAll(Map<String, dynamic> incoming) async {
    final current = await exportAll();
    final merged = mergeFinanceDatabasePayloads(current, incoming);
    await importAll(merged.database);
    return merged.categoryPlan;
  }

  Future<bool> hasLocalUserActivity() async {
    final database = await db;
    for (final table in ['planned_purchases', 'transactions', 'budgets', 'loans']) {
      final rows = await database.query(table, columns: ['COUNT(*) AS count']);
      if ((rows.first['count'] as num? ?? 0).toInt() > 0) return true;
    }
    return false;
  }

  Future<void> clearFinanceDataForRemoteLogin() async {
    final database = await db;
    final tables = ['loan_payments', 'loans', 'loan_contacts', 'budget_categories', 'budget_accounts', 'budgets', 'transactions', 'planned_purchases', 'categories', 'accounts'];
    await database.transaction((txn) async {
      for (final table in tables) {
        await txn.delete(table);
      }
      await txn.delete('sync_outbox');
      await txn.delete('sync_entity_versions');
      await txn.delete('sync_conflicts');
    });
  }

  static const syncTables = [
    'accounts',
    'categories',
    'planned_purchases',
    'transactions',
    'budgets',
    'budget_accounts',
    'budget_categories',
    'loan_contacts',
    'loans',
    'loan_payments',
  ];

  Future<String> readSyncState(String key, [String fallback = '']) async {
    final rows = await (await db).query('sync_state', columns: ['value'], where: 'key = ?', whereArgs: [key], limit: 1);
    return rows.isEmpty ? fallback : rows.first['value'] as String? ?? fallback;
  }

  Future<void> writeSyncState(String key, String value) async {
    await (await db).insert('sync_state', {'key': key, 'value': value}, conflictAlgorithm: sql.ConflictAlgorithm.replace);
  }

  Future<int> localEntityVersion(String entityType, String entityId) async {
    final rows = await (await db).query('sync_entity_versions', columns: ['version'], where: 'entity_type = ? AND entity_id = ?', whereArgs: [entityType, entityId], limit: 1);
    return rows.isEmpty ? 0 : (rows.first['version'] as num? ?? 0).toInt();
  }

  Future<void> saveEntityVersion(String entityType, String entityId, int version) async {
    await (await db).insert(
      'sync_entity_versions',
      {'entity_type': entityType, 'entity_id': entityId, 'version': version},
      conflictAlgorithm: sql.ConflictAlgorithm.replace,
    );
  }

  Future<void> enqueueTableRow(String table, String entityId, {String operation = 'upsert'}) async {
    if (!syncTables.contains(table)) return;
    Map<String, Object?>? payload;
    if (operation != 'delete') {
      final rows = await (await db).query(table, where: _whereForEntity(table), whereArgs: _whereArgsForEntity(table, entityId), limit: 1);
      if (rows.isEmpty) return;
      payload = rows.first;
    }
    await enqueueSyncOperation(entityType: table, entityId: entityId, operation: operation, payload: payload);
  }

  Future<void> enqueueRowsForTable(String table, {String? budgetId}) async {
    if (!syncTables.contains(table)) return;
    final rows = await (await db).query(table, where: budgetId == null ? null : 'budget_id = ?', whereArgs: budgetId == null ? null : [budgetId]);
    for (final row in rows) {
      final entityId = _entityIdForRow(table, row);
      if (entityId.isNotEmpty) {
        await enqueueSyncOperation(entityType: table, entityId: entityId, operation: 'upsert', payload: row);
      }
    }
  }

  Future<void> enqueueDelete(String table, String entityId) async {
    await enqueueSyncOperation(entityType: table, entityId: entityId, operation: 'delete', payload: null);
  }

  Future<void> enqueuePreferences(Map<String, dynamic> preferences) async {
    await enqueueSyncOperation(entityType: 'preferences', entityId: 'koinly', operation: 'upsert', payload: preferences);
  }

  Future<void> enqueueAllForAdoption(Map<String, dynamic> preferences) async {
    for (final table in syncTables) {
      await enqueueRowsForTable(table);
    }
    await enqueuePreferences(preferences);
  }

  Future<void> resetLocalSyncTracking() async {
    final database = await db;
    await database.transaction((txn) async {
      await txn.delete('sync_outbox');
      await txn.delete('sync_entity_versions');
      await txn.delete('sync_conflicts');
    });
  }

  Future<void> enqueueSyncOperation({
    required String entityType,
    required String entityId,
    required String operation,
    required Map<String, Object?>? payload,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final id = _uuid.v4();
    await (await db).insert('sync_outbox', {
      'id': id,
      'entity_type': entityType,
      'entity_id': entityId,
      'operation': operation,
      'payload_json': payload == null ? null : jsonEncode(payload),
      'base_version': await localEntityVersion(entityType, entityId),
      'created_at': now,
    });
  }

  Future<List<Map<String, Object?>>> pendingSyncOperations({int limit = 50}) async {
    return (await db).query('sync_outbox', orderBy: 'created_at ASC', limit: limit);
  }

  Future<Map<String, Object?>?> syncEntityRow(String entityType, String entityId) async {
    if (!syncTables.contains(entityType) || entityId.isEmpty) return null;
    final rows = await (await db).query(
      entityType,
      where: _whereForEntity(entityType),
      whereArgs: _whereArgsForEntity(entityType, entityId),
      limit: 1,
    );
    return rows.isEmpty ? null : Map<String, Object?>.from(rows.first);
  }

  Future<void> upsertSyncEntityRow(String entityType, Map<String, Object?> payload) async {
    if (!syncTables.contains(entityType)) return;
    await (await db).insert(entityType, payload, conflictAlgorithm: sql.ConflictAlgorithm.replace);
  }

  Future<int> pendingSyncOperationCount() async {
    final count = sql.Sqflite.firstIntValue(await (await db).rawQuery('SELECT COUNT(*) FROM sync_outbox'));
    return count ?? 0;
  }

  Future<int> openSyncConflictCount() async {
    final count = sql.Sqflite.firstIntValue(await (await db).rawQuery('SELECT COUNT(*) FROM sync_conflicts WHERE resolved_at IS NULL'));
    return count ?? 0;
  }

  Future<void> markOutboxUploaded(List<String> operationIds, Map<String, int> versionsByOperationId) async {
    if (operationIds.isEmpty) return;
    final database = await db;
    await database.transaction((txn) async {
      for (final operationId in operationIds) {
        final rows = await txn.query('sync_outbox', where: 'id = ?', whereArgs: [operationId], limit: 1);
        if (rows.isEmpty) continue;
        final row = rows.first;
        final version = versionsByOperationId[operationId];
        if (version != null) {
          await txn.insert(
            'sync_entity_versions',
            {'entity_type': row['entity_type'], 'entity_id': row['entity_id'], 'version': version},
            conflictAlgorithm: sql.ConflictAlgorithm.replace,
          );
        }
        await txn.delete('sync_outbox', where: 'id = ?', whereArgs: [operationId]);
      }
    });
  }

  Future<void> markOutboxFailed(String operationId, Object error) async {
    await (await db).rawUpdate(
      'UPDATE sync_outbox SET attempt_count = attempt_count + 1, last_attempt_at = ?, last_error = ? WHERE id = ?',
      [DateTime.now().millisecondsSinceEpoch, redactSyncSecrets(error.toString()), operationId],
    );
  }

  Future<void> saveSyncConflict({
    required String entityType,
    required String entityId,
    required String? localOperationId,
    required int serverVersion,
    required String details,
  }) async {
    final database = await db;
    final existing = await database.query(
      'sync_conflicts',
      columns: ['id'],
      where: 'entity_type = ? AND entity_id = ? AND resolved_at IS NULL',
      whereArgs: [entityType, entityId],
      orderBy: 'created_at DESC',
      limit: 1,
    );
    final values = <String, Object?>{
      'entity_type': entityType,
      'entity_id': entityId,
      'local_operation_id': localOperationId,
      'server_version': serverVersion,
      'details': details,
      'created_at': DateTime.now().millisecondsSinceEpoch,
      'resolved_at': null,
    };
    if (existing.isNotEmpty) {
      await database.update('sync_conflicts', values, where: 'id = ?', whereArgs: [existing.first['id']]);
      return;
    }
    await database.insert('sync_conflicts', {'id': _uuid.v4(), ...values});
  }

  /// A conflict is settled once the merge/rebase pass has completed and there
  /// is no longer an outstanding local operation for that same entity. Keeping
  /// the historical row is useful for diagnostics, but it must no longer count
  /// as an open conflict after both sides have converged.
  Future<int> resolveSettledSyncConflicts({int? settledThrough}) async {
    final database = await db;
    final now = DateTime.now().millisecondsSinceEpoch;
    final cutoff = settledThrough ?? now;
    return database.rawUpdate('''
      UPDATE sync_conflicts
      SET resolved_at = ?
      WHERE resolved_at IS NULL
        AND created_at <= ?
        AND NOT EXISTS (
          SELECT 1
          FROM sync_outbox
          WHERE sync_outbox.entity_type = sync_conflicts.entity_type
            AND sync_outbox.entity_id = sync_conflicts.entity_id
        )
    ''', [now, cutoff]);
  }

  Future<bool> applyRemoteChanges(List<Map<String, dynamic>> changes, Future<void> Function(Map<String, dynamic>) applyPreferences) async {
    // __reset__ is a legacy cloud marker from the old replace-all flow. Merge
    // sync never clears local finance data because an item is absent remotely.
    // For a matching stable ID, a newer local row is retained and rebased onto
    // the server version so it can be pushed normally after the merge.
    final database = await db;
    final preservedLocalRows = <({String entityType, String entityId, Map<String, Object?> payload})>[];
    await database.transaction((txn) async {
      for (final change in changes) {
        final entityType = change['entityType'] as String? ?? '';
        final entityId = change['entityId'] as String? ?? '';
        final operation = change['operation'] as String? ?? '';
        final version = (change['version'] as num? ?? 0).toInt();
        if (entityType == '__reset__') continue;
        if (entityType == 'preferences') continue;
        if (!syncTables.contains(entityType) || entityId.isEmpty) continue;
        if (operation == 'delete') {
          if (entityType == 'budgets') {
            await txn.delete('budget_accounts', where: 'budget_id = ?', whereArgs: [entityId]);
            await txn.delete('budget_categories', where: 'budget_id = ?', whereArgs: [entityId]);
          }
          if (entityType == 'loans') {
            await txn.delete('loan_payments', where: 'loan_id = ?', whereArgs: [entityId]);
          }
          await txn.delete(entityType, where: _whereForEntity(entityType), whereArgs: _whereArgsForEntity(entityType, entityId));
        } else {
          final payload = (change['payload'] as Map? ?? {}).cast<String, Object?>();
          var keepLocal = false;
          Map<String, Object?>? localRow;
          // Join tables do not carry modification timestamps; their composite
          // IDs already provide set-union semantics, so server upserts are safe.
          if (entityType != 'budget_accounts' && entityType != 'budget_categories') {
            final localRows = await txn.query(
              entityType,
              where: _whereForEntity(entityType),
              whereArgs: _whereArgsForEntity(entityType, entityId),
              limit: 1,
            );
            if (localRows.isNotEmpty) {
              localRow = Map<String, Object?>.from(localRows.first);
              keepLocal = _syncRowTimestamp(localRow) > _syncRowTimestamp(payload);
            }
          }
          if (keepLocal && localRow != null) {
            preservedLocalRows.add((entityType: entityType, entityId: entityId, payload: localRow));
          } else {
            await txn.insert(entityType, payload, conflictAlgorithm: sql.ConflictAlgorithm.replace);
          }
        }
        await txn.insert(
          'sync_entity_versions',
          {'entity_type': entityType, 'entity_id': entityId, 'version': version},
          conflictAlgorithm: sql.ConflictAlgorithm.replace,
        );
      }
    });
    for (final change in changes) {
      if (change['entityType'] == 'preferences' && change['operation'] == 'upsert') {
        final payload = (change['payload'] as Map? ?? {}).cast<String, dynamic>();
        await applyPreferences(payload);
        await saveEntityVersion('preferences', 'koinly', (change['version'] as num? ?? 0).toInt());
      }
    }
    for (final local in preservedLocalRows) {
      await enqueueSyncOperation(
        entityType: local.entityType,
        entityId: local.entityId,
        operation: 'upsert',
        payload: local.payload,
      );
    }
    return preservedLocalRows.isNotEmpty;
  }

  int _syncRowTimestamp(Map<String, Object?> row) {
    for (final key in const ['updated_on', 'created_on']) {
      final value = row[key];
      if (value is num) return value.toInt();
      if (value is String) {
        final parsedInt = int.tryParse(value);
        if (parsedInt != null) return parsedInt;
        final parsedDate = DateTime.tryParse(value);
        if (parsedDate != null) return parsedDate.millisecondsSinceEpoch;
      }
    }
    return 0;
  }

  String _whereForEntity(String table) {
    switch (table) {
      case 'budget_accounts':
      case 'budget_categories':
        return 'budget_id = ? AND ${table == 'budget_accounts' ? 'account_id' : 'category_id'} = ?';
      default:
        return 'id = ?';
    }
  }

  List<Object?> _whereArgsForEntity(String table, String entityId) {
    switch (table) {
      case 'budget_accounts':
      case 'budget_categories':
        final parts = entityId.split(':');
        return [parts.first, parts.length > 1 ? parts[1] : ''];
      default:
        return [entityId];
    }
  }

  String _entityIdForRow(String table, Map<String, Object?> row) {
    switch (table) {
      case 'budget_accounts':
        return '${row['budget_id']}:${row['account_id']}';
      case 'budget_categories':
        return '${row['budget_id']}:${row['category_id']}';
      default:
        return row['id']?.toString() ?? '';
    }
  }
}

enum AutoBackupFrequency { daily, weekly, monthly }

class AutomaticBackupDirectorySelection {
  const AutomaticBackupDirectorySelection({
    required this.path,
    required this.uri,
    required this.label,
  });

  const AutomaticBackupDirectorySelection.appStorage()
      : path = '',
        uri = '',
        label = 'Koinly app storage';

  final String path;
  final String uri;
  final String label;
}

class BackupService {
  static const String safetyBackupPrefix = 'koinly_safety_';
  static const String automaticBackupPrefix = 'koinly_auto_';
  static const int maxSafetyBackups = 3;

  static String _crypt(String source) {
    final key = utf8.encode(backupPassword);
    final bytes = utf8.encode(source);
    final out = List<int>.generate(bytes.length, (i) => bytes[i] ^ key[i % key.length]);
    return base64Encode(out);
  }

  static String _decrypt(String source) {
    final key = utf8.encode(backupPassword);
    final bytes = base64Decode(source);
    final out = List<int>.generate(bytes.length, (i) => bytes[i] ^ key[i % key.length]);
    return utf8.decode(out);
  }

  static String backupFileName() {
    return 'koinly_backup_${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}.koinlybackup';
  }

  static String safetyBackupFileName() {
    return '${safetyBackupPrefix}${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.koinlybackup';
  }

  static String automaticBackupFileName() {
    return '${automaticBackupPrefix}${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.koinlybackup';
  }

  static Future<Directory> backupStorageDirectory() async {
    final dir = await getApplicationDocumentsDirectory();
    final backupsDir = Directory(p.join(dir.path, 'backups'));
    if (!await backupsDir.exists()) {
      await backupsDir.create(recursive: true);
    }
    return backupsDir;
  }

  static Future<File> createBackup(AppController state) async {
    final dir = await getTemporaryDirectory();
    final normalized = normalizeCategoryDatabasePayload(await state.database.exportAll());
    final payload = {
      'version': 7,
      'created_at': DateTime.now().toIso8601String(),
      'database': normalized.database,
      'preferences': remapCategoryPreferences(await state.exportPreferences(), normalized.plan),
    };
    final file = File(p.join(dir.path, backupFileName()));
    await file.writeAsString(_crypt(jsonEncode(payload)));
    return file;
  }

  static Future<File> createSafetyBackup(AppController state, {required String reason}) async {
    final backupsDir = await backupStorageDirectory();
    final normalized = normalizeCategoryDatabasePayload(await state.database.exportAll());
    final payload = {
      'version': 7,
      'backup_type': 'safety',
      'reason': reason,
      'created_at': DateTime.now().toIso8601String(),
      'database': normalized.database,
      'preferences': remapCategoryPreferences(await state.exportPreferences(), normalized.plan),
    };
    final file = File(p.join(backupsDir.path, safetyBackupFileName()));
    await file.writeAsString(_crypt(jsonEncode(payload)));
    await pruneSafetyBackups();
    return file;
  }

  static Future<void> pruneSafetyBackups() async {
    final backupsDir = await backupStorageDirectory();
    final files = await backupsDir
        .list()
        .where((entity) => entity is File && p.basename(entity.path).startsWith(safetyBackupPrefix) && entity.path.endsWith('.koinlybackup'))
        .cast<File>()
        .toList();
    files.sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
    for (final stale in files.skip(maxSafetyBackups)) {
      try {
        await stale.delete();
      } catch (_) {
        // A stale safety backup should never block a real backup/restore flow.
      }
    }
  }

  static Future<Directory> automaticBackupDirectory(String configuredPath) async {
    final normalized = configuredPath.trim();
    if (normalized.isEmpty) {
      throw StateError('Choose a backup folder before enabling automatic backup.');
    }
    final directory = Directory(normalized);
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return directory;
  }

  static Future<String> createAutomaticBackup(
    AppController state, {
    required String directoryPath,
    required String directoryUri,
    required String directoryLabel,
    required bool deleteOlderBackups,
  }) async {
    final normalized = normalizeCategoryDatabasePayload(await state.database.exportAll());
    final payload = {
      'version': 7,
      'backup_type': 'automatic',
      'created_at': DateTime.now().toIso8601String(),
      'database': normalized.database,
      'preferences': remapCategoryPreferences(await state.exportPreferences(), normalized.plan),
    };
    final fileName = automaticBackupFileName();
    final encryptedBytes = Uint8List.fromList(utf8.encode(_crypt(jsonEncode(payload))));

    if (Platform.isAndroid && directoryUri.trim().isNotEmpty) {
      final canWrite = await AndroidSafBackupStore.canWrite(directoryUri.trim());
      if (!canWrite) {
        throw StateError('Koinly no longer has permission to write to this Android folder. Choose the folder again.');
      }
      await AndroidSafBackupStore.writeFile(
        uri: directoryUri.trim(),
        name: fileName,
        bytes: encryptedBytes,
      );
      if (deleteOlderBackups) {
        await pruneAndroidAutomaticBackups(directoryUri.trim());
      }
      final label = directoryLabel.trim().isEmpty ? 'Selected Android folder' : directoryLabel.trim();
      return '$label/$fileName';
    }

    if (Platform.isAndroid && directoryPath.trim().isNotEmpty) {
      throw StateError('Android folder permission is missing. Choose the backup folder again so Koinly can save through Android folder access.');
    }
    if (directoryPath.trim().isEmpty) {
      throw StateError('Choose a backup folder before enabling automatic backup.');
    }

    final directory = await automaticBackupDirectory(directoryPath);
    final file = File(p.join(directory.path, fileName));
    await file.writeAsBytes(encryptedBytes, flush: true);
    if (deleteOlderBackups) {
      await pruneAutomaticBackups(directory);
    }
    return file.path;
  }

  static Future<void> pruneAutomaticBackups(Directory directory) async {
    final files = await directory
        .list()
        .where((entity) =>
            entity is File &&
            p.basename(entity.path).startsWith(automaticBackupPrefix) &&
            entity.path.toLowerCase().endsWith('.koinlybackup'))
        .cast<File>()
        .toList();
    files.sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
    for (final stale in files.skip(1)) {
      try {
        await stale.delete();
      } catch (_) {
        // Retention cleanup should not invalidate a backup that was just written.
      }
    }
  }

  static Future<void> pruneAndroidAutomaticBackups(String directoryUri) async {
    final files = (await AndroidSafBackupStore.listFiles(directoryUri))
        .where((entry) => entry.name.startsWith(automaticBackupPrefix) && entry.name.toLowerCase().endsWith('.koinlybackup'))
        .toList()
      ..sort((a, b) => b.lastModified.compareTo(a.lastModified));
    for (final stale in files.skip(1)) {
      try {
        await AndroidSafBackupStore.deleteFile(uri: directoryUri, name: stale.name);
      } catch (_) {
        // Keep the new backup even if an older file could not be pruned.
      }
    }
  }

  static Future<AutomaticBackupDirectorySelection?> pickAutomaticBackupDirectory() async {
    try {
      if (Platform.isAndroid) {
        final selected = await AndroidSafBackupStore.pickDirectory();
        if (selected == null) return null;
        return AutomaticBackupDirectorySelection(path: '', uri: selected.uri, label: selected.label);
      }
      final path = await FilePicker.platform.getDirectoryPath(dialogTitle: 'Choose where Koinly/Backup should be created');
      if (path == null || path.trim().isEmpty) return null;
      final selected = p.normalize(path.trim());
      final selectedName = p.basename(selected).toLowerCase();
      final parentName = p.basename(p.dirname(selected)).toLowerCase();
      final alreadyBackupFolder = selectedName == 'backup' && parentName == 'koinly';
      final backupPath = alreadyBackupFolder
          ? selected
          : selectedName == 'koinly'
              ? p.join(selected, 'Backup')
              : p.join(selected, 'Koinly', 'Backup');
      await Directory(backupPath).create(recursive: true);
      return AutomaticBackupDirectorySelection(path: backupPath, uri: '', label: backupPath);
    } catch (_) {
      return null;
    }
  }

  static Future<File> saveBackupToAppStorage(File source, {String? fileName}) async {
    final backupsDir = await backupStorageDirectory();
    final target = File(p.join(backupsDir.path, fileName ?? p.basename(source.path)));
    return source.copy(target.path);
  }

  static const List<String> _backupFinanceTables = <String>[
    'accounts',
    'categories',
    'planned_purchases',
    'transactions',
    'budgets',
    'budget_accounts',
    'budget_categories',
    'loan_contacts',
    'loans',
    'loan_payments',
  ];

  static int financeRecordCount(Map<String, dynamic> database) {
    var count = 0;
    for (final table in _backupFinanceTables) {
      final rows = database[table];
      if (rows is List) count += rows.whereType<Map>().length;
    }
    return count;
  }

  static Future<void> restoreBackupFile(AppController state, File file) async {
    final encrypted = await file.readAsString();
    final payload = jsonDecode(_decrypt(encrypted)) as Map<String, dynamic>;
    final incomingDatabase = (payload['database'] as Map? ?? const {}).cast<String, dynamic>();
    final incomingRecordCount = financeRecordCount(incomingDatabase);
    if (incomingRecordCount == 0) {
      throw const FormatException(
        'This backup contains no finance records. If it came from Telegram, sync/upload your local data to the self-hosted Worker and create a new backup.',
      );
    }

    // A restore is an import/merge flow, not a "Start new" flow. Remove only
    // untouched built-in account placeholders before folding in the backup so
    // a restored Cash account does not sit beside Koinly's preloaded Cash.
    await state.discardPreloadedStarterAccountsForImport();

    final currentPreferences = await state.exportPreferences();
    final incomingPreferences = (payload['preferences'] as Map? ?? {}).cast<String, dynamic>();
    final plan = await state.database.mergeAll(incomingDatabase);
    final mergedPreferences = mergeFinancePreferences(currentPreferences, incomingPreferences, plan);
    await state.importPreferences(mergedPreferences);
    await state.reload(queueSync: false);
    // Old backups can themselves contain never-used starter placeholders from
    // versions that seeded accounts before onboarding. Remove those after the
    // merge as well, while preserving any starter account that has balance,
    // credit, transaction, budget, or customization evidence.
    await state.discardPreloadedStarterAccountsForImport();
  }

  static Future<File?> pickBackupFile() async {
    FilePickerResult? picked;
    try {
      picked = await FilePicker.platform.pickFiles(
        dialogTitle: 'Load Koinly backup',
        type: FileType.custom,
        allowedExtensions: const ['koinlybackup'],
      );
    } catch (_) {
      picked = await FilePicker.platform.pickFiles(type: FileType.any);
    }
    if (picked == null || picked.files.single.path == null) return null;
    final file = File(picked.files.single.path!);
    if (!file.path.toLowerCase().endsWith('.koinlybackup')) {
      throw const FormatException('Please select a Koinly .koinlybackup file.');
    }
    return file;
  }

  static Future<bool> restoreBackup(AppController state, {String? safetyReason}) async {
    final file = await pickBackupFile();
    if (file == null) return false;
    if (safetyReason != null) {
      await state.requireSafetyBackup(safetyReason);
    }
    await restoreBackupFile(state, file);
    return true;
  }
}

Future<void> runBackupFlow(BuildContext context, AppController state) async {
  try {
    final tempFile = await BackupService.createBackup(state);
    final fileName = p.basename(tempFile.path);
    final fileBytes = await tempFile.readAsBytes();

    String? savedPath;
    try {
      savedPath = await FilePicker.platform.saveFile(
        dialogTitle: 'Save Koinly backup',
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: const ['koinlybackup'],
        bytes: fileBytes,
      );
    } catch (_) {
      savedPath = null;
    }

    final localFile = await BackupService.saveBackupToAppStorage(tempFile, fileName: fileName);

    if (context.mounted) {
      if (savedPath == null) {
        showSnack(context, 'Backup saved to local app storage.');
      } else {
        showSnack(context, 'Backup saved to local storage.');
      }
    }

    if (localFile.path.isEmpty) {
      throw const FileSystemException('Backup file was not saved.');
    }
  } catch (_) {
    if (context.mounted) {
      showSnack(context, 'Backup failed. Please try again.');
    }
  }
}

Future<void> runRestoreFlow(BuildContext context, AppController state) async {
  try {
    final restored = await BackupService.restoreBackup(state, safetyReason: 'Before manual backup restore');
    if (!restored) return;
    await state.markRestoredDataForCloudUpload();
    if (context.mounted) {
      showSnack(
        context,
        state.cloudSyncEnabled ? 'Backup merged with this device and queued for cloud merge.' : 'Backup merged with this device. Sign in to sync the merged data.',
      );
    }
  } catch (_) {
    if (context.mounted) {
      showSnack(context, 'Restore failed. Please check the backup file.');
    }
  }
}

Future<void> runLoadBackupFlow(BuildContext context, AppController state) async {
  try {
    final restored = await BackupService.restoreBackup(state, safetyReason: 'Before loading backup file');
    if (!restored) {
      if (context.mounted) showSnack(context, 'Load cancelled.');
      return;
    }
    await state.markRestoredDataForCloudUpload();
    if (context.mounted) {
      showSnack(
        context,
        state.cloudSyncEnabled ? 'Backup merged with local data and queued for cloud merge.' : 'Backup merged with local data.',
      );
    }
  } on FormatException catch (e) {
    if (context.mounted) {
      showSnack(context, e.message);
    }
  } catch (_) {
    if (context.mounted) {
      showSnack(context, 'Could not load backup. Please choose a valid Koinly backup file.');
    }
  }
}

Future<void> runRestoreLastSafetyBackupFlow(BuildContext context, AppController state) async {
  try {
    final restored = await state.restoreLastSafetyBackup();
    if (!restored) {
      if (context.mounted) showSnack(context, 'No safety backup is available yet.');
      return;
    }
    if (context.mounted) {
      showSnack(
        context,
        state.cloudSyncEnabled ? 'Safety backup merged with local data and queued for cloud merge.' : 'Safety backup merged with local data.',
      );
    }
  } catch (_) {
    if (context.mounted) {
      showSnack(context, 'Could not restore the safety backup.');
    }
  }
}

Future<void> copyDiagnosticsReportFlow(BuildContext context, AppController state) async {
  try {
    final report = await state.buildDiagnosticsReport();
    await Clipboard.setData(ClipboardData(text: report));
    if (context.mounted) showSnack(context, 'Diagnostics report copied.');
  } catch (_) {
    if (context.mounted) showSnack(context, 'Could not build diagnostics report.');
  }
}

Future<void> shareDiagnosticsReportFlow(BuildContext context, AppController state) async {
  try {
    final report = await state.buildDiagnosticsReport();
    await Share.share(report, subject: 'Koinly diagnostics');
  } catch (_) {
    if (context.mounted) showSnack(context, 'Could not share diagnostics report.');
  }
}


// -----------------------------------------------------------------------------
// Controller
// -----------------------------------------------------------------------------

class AppController extends ChangeNotifier {
  final database = KoinlyDatabase();
  final prefs = PrefsStore();
  final secureCredentials = SecureCredentialStore();
  final profileMediaStorage = const ProfileMediaStorage();
  final profileMediaPermissions = const ProfileMediaPermissionService();
  static final NumberFormat _groupedAmountFormatter = NumberFormat('#,##0.##');
  static final NumberFormat _plainAmountFormatter = NumberFormat('0.##');

  bool loading = true;
  bool onboardingCompleted = false;
  bool starterAccountsSkipped = false;
  int desktopSetupVersionCompleted = 0;
  int tabIndex = 0;

  List<Account> accounts = [];
  List<Category> categories = [];
  List<PlannedPurchase> plannedPurchases = [];
  List<MoneyTransaction> transactions = [];
  List<Budget> budgets = [];
  LoanRepository? _loanRepository;
  List<LoanContact> loanContacts = [];
  List<Loan> loans = [];
  List<LoanPayment> loanPayments = [];
  String profileDisplayName = '';
  String profileMediaPath = '';
  String profileMediaOriginalName = '';
  ProfileMediaKind? profileMediaKind;
  int profileMediaSizeBytes = 0;
  double profileMediaScale = 1.0;
  double profileMediaAlignmentX = 0.0;
  double profileMediaAlignmentY = 0.0;
  List<String> dismissedFinancialHealthSummaryKeys = [];
  Map<String, Account> _accountsById = {};
  Map<String, Category> _categoriesById = {};
  Map<String, LoanContact> _loanContactsById = {};
  Map<String, Loan> _loansById = {};
  Map<String, List<LoanPayment>> _paymentsByLoan = {};
  Map<CategoryType, Set<String>> _categoryIdsByType = {
    CategoryType.income: <String>{},
    CategoryType.expense: <String>{},
  };
  List<Account> _operatingAccounts = [];
  List<Account> _savingAccounts = [];
  double _operatingAccountBalance = 0;
  double _savingAccountBalance = 0;
  double _totalAccountBalance = 0;

  ThemePreference themePreference = ThemePreference.system;
  String currencySymbol = '৳';
  String currencyCode = 'BDT';
  CurrencyPosition currencyPosition = CurrencyPosition.suffix;
  bool useSeparators = true;
  bool amountsHidden = false;
  DateRangeType dateRangeType = DateRangeType.thisMonth;
  DateTime? customStart;
  DateTime? customEnd;
  List<String> filterAccountIds = [];
  List<String> filterCategoryIds = [];
  List<MoneyTransactionType> filterTypes = [];
  String? defaultAccountId;
  String? defaultExpenseCategoryId;
  String? defaultIncomeCategoryId;
  bool compactHomeSummary = false;
  bool reminderEnabled = false;
  TimeOfDay reminderTime = const TimeOfDay(hour: 21, minute: 0);
  bool loanRecordTransactionsByDefault = true;
  bool loanRemindersEnabled = true;
  bool loanShowWrittenOff = false;
  bool loanTransactionsVisibleInTransactionList = true;
  bool cloudSyncEnabled = false;
  SyncDatabaseProvider syncDatabaseProvider = SyncDatabaseProvider.mongoDb;
  String selfHostedSyncApiBaseUrl = '';
  String cloudSyncApiBaseUrl = '';
  String cloudSyncId = '';
  String cloudSyncPin = '';
  String syncMongoDbUrl = '';
  String syncMongoDatabaseName = MongoDbSyncService.defaultDatabaseName;
  String syncMongoCollectionName = MongoDbSyncService.defaultCollectionName;
  String syncMongoSyncId = '';
  String syncMongoSyncPin = '';
  String syncTursoDatabaseUrl = '';
  String syncTursoAuthToken = '';
  bool cloudSyncBusy = false;
  bool cloudSyncPending = false;
  bool authoritativeCloudUploadPending = false;
  bool newSyncAccountAwaitingSetupChoice = false;
  String? cloudSyncError;
  String? cloudSyncErrorCode;
  DateTime? cloudSyncLastAt;
  bool _syncInProgress = false;
  Timer? _cloudSyncDebounce;
  Timer? _cloudSyncRetryTimer;
  Timer? _cloudSyncAutoPullTimer;
  Timer? _cloudSyncLiveReconnectTimer;
  StreamSubscription<dynamic>? _cloudSyncLiveSubscription;
  WebSocket? _cloudSyncLiveSocket;
  DateTime? _lastCloudAutoPullAt;
  Duration? _cloudSyncActivePullInterval;
  bool _cloudSyncLiveConnecting = false;
  bool _cloudRealtimePullPending = false;
  int _cloudSyncLiveReconnectAttempt = 0;
  // Realtime notifications are delivered through the self-hosted Worker's
  // WebSocket hub. Local writes are pushed after a very short debounce; the
  // slower timer remains only as a resilience fallback when the live channel
  // is unavailable or the platform temporarily suspends it.
  static const Duration _cloudSyncPushDebounce = Duration(milliseconds: 120);
  static const Duration _cloudSyncRealtimeFallbackInterval = Duration(seconds: 20);
  static const Duration _cloudSyncDisconnectedFallbackInterval = Duration(seconds: 3);
  static const Duration _cloudSyncAutoPullMinimumGap = Duration(milliseconds: 750);
  static const Duration _cloudSyncRetryInterval = Duration(seconds: 5);
  String syncAccountUsername = '';
  String syncAccessToken = '';
  String syncRefreshToken = '';
  String syncDeviceId = '';
  String syncStatus = 'Offline';
  bool syncAuthBusy = false;
  final GithubUpdateService updateService = GithubUpdateService();
  UpdateCheckOutcome updateCheckOutcome = UpdateCheckOutcome.noReleaseAvailable;
  bool updateCheckBusy = false;
  bool automaticUpdatePopupEnabled = true;

  bool get cloudSyncOperationBusy => _syncInProgress || cloudSyncBusy || syncAuthBusy;
  bool updateDownloadBusy = false;
  String updateStatusMessage = 'Not checked yet.';
  DateTime? updateLastCheckedAt;
  GithubRelease? latestGithubRelease;
  UpdateAssetKind selectedAndroidUpdateKind = UpdateAssetKind.arm64;
  DownloadProgressSnapshot? updateDownloadProgress;
  String pendingAndroidUpdatePath = '';
  String pendingAndroidUpdateVersion = '';
  UpdateAssetKind? pendingAndroidUpdateKind;
  String pendingWindowsUpdatePath = '';
  String pendingWindowsUpdateVersion = '';
  String lastSafetyBackupPath = '';
  DateTime? lastSafetyBackupAt;
  bool autoBackupEnabled = false;
  AutoBackupFrequency autoBackupFrequency = AutoBackupFrequency.daily;
  int autoBackupHour = 2;
  int autoBackupMinute = 0;
  int autoBackupWeekday = DateTime.sunday;
  int autoBackupMonthDay = 1;
  bool autoBackupDeleteOlder = true;
  String autoBackupDirectoryPath = '';
  String autoBackupDirectoryUri = '';
  String autoBackupDirectoryLabel = '';
  String lastAutoBackupPath = '';
  DateTime? lastAutoBackupAt;
  String? autoBackupError;
  bool _autoBackupInFlight = false;
  Timer? _autoBackupTimer;
  DataHealthReport? dataHealthReport;
  bool dataHealthBusy = false;
  String? _shownUpdateDialogVersionThisSession;
  http.Client? _updateDownloadClient;
  bool _updateDownloadCancelled = false;

  bool get setupCompletedForCurrentPlatform {
    if (!onboardingCompleted) return false;
    if (!kIsDesktopApp) return true;
    return desktopSetupVersionCompleted >= kRequiredDesktopSetupVersion;
  }

  bool get hasProfileMedia =>
      profileMediaPath.trim().isNotEmpty &&
      profileMediaKind != null &&
      File(profileMediaPath).existsSync();

  String get profileDisplayLabel {
    final customName = profileDisplayName.trim();
    if (customName.isNotEmpty) return customName;
    final username = syncAccountUsername.trim();
    return username.isEmpty ? 'Profile' : username;
  }

  void selectTabIndex(int index) {
    if (tabIndex == index) return;
    tabIndex = index;
    notifyListeners();
  }

  Future<void> initialize() async {
    await database.db;
    await _loadPreferences();
    await reload();
    // v1.0.1065-1067 could merge a restored account set on top of the old
    // built-in starter rows. A duplicate starter fingerprint is strong legacy
    // evidence of that bug, so clean all still-untouched built-in placeholders
    // once on upgrade while leaving used/customized accounts intact.
    if (await database.hasRedundantPreloadedStarterAccountEvidence()) {
      await discardPreloadedStarterAccountsForImport();
      await reload(queueSync: false);
    }
    loading = false;
    notifyListeners();
    try {
      await FirebaseAnalytics.instance.logAppOpen();
    } catch (_) {}
    if (_hasConfiguredSyncTarget() && !newSyncAccountAwaitingSetupChoice) {
      _schedulePendingSyncRetry(immediate: true);
      _startCloudAutoPull();
    }
    unawaited(runAutomaticBackupIfDue());
  }

  Future<void> _loadPreferences() async {
    onboardingCompleted = await prefs.getBool('onboardingCompleted', false);
    starterAccountsSkipped = await prefs.getBool('starterAccountsSkipped', false);
    desktopSetupVersionCompleted = await prefs.getInt('desktopSetupVersionCompleted', 0);
    themePreference = await prefs.getEnum('themePreference', ThemePreference.values, ThemePreference.system);
    currencySymbol = await prefs.getString('currencySymbol', '৳');
    currencyCode = await prefs.getString('currencyCode', 'BDT');
    currencyPosition = await prefs.getEnum('currencyPosition', CurrencyPosition.values, CurrencyPosition.suffix);
    useSeparators = await prefs.getBool('useSeparators', true);
    amountsHidden = await prefs.getBool('amountsHidden', false);
    profileDisplayName = await prefs.getString('profileDisplayName', '');
    profileMediaPath = await prefs.getString('profileMediaPath', '');
    profileMediaOriginalName = await prefs.getString('profileMediaOriginalName', '');
    profileMediaSizeBytes = await prefs.getInt('profileMediaSizeBytes', 0);
    profileMediaScale = double.tryParse(await prefs.getString('profileMediaScale', '1.0')) ?? 1.0;
    profileMediaAlignmentX = double.tryParse(await prefs.getString('profileMediaAlignmentX', '0.0')) ?? 0.0;
    profileMediaAlignmentY = double.tryParse(await prefs.getString('profileMediaAlignmentY', '0.0')) ?? 0.0;
    profileMediaScale = profileMediaScale.clamp(1.0, 3.0).toDouble();
    profileMediaAlignmentX = profileMediaAlignmentX.clamp(-1.0, 1.0).toDouble();
    profileMediaAlignmentY = profileMediaAlignmentY.clamp(-1.0, 1.0).toDouble();
    final profileMediaKindName = await prefs.getString('profileMediaKind', '');
    profileMediaKind = profileMediaKindName.isEmpty
        ? null
        : enumByName(ProfileMediaKind.values, profileMediaKindName, ProfileMediaKind.photo);
    if (profileMediaPath.isNotEmpty && !File(profileMediaPath).existsSync()) {
      profileMediaPath = '';
      profileMediaOriginalName = '';
      profileMediaSizeBytes = 0;
      profileMediaKind = null;
      profileMediaScale = 1.0;
      profileMediaAlignmentX = 0.0;
      profileMediaAlignmentY = 0.0;
      final sharedPreferences = await prefs.prefs;
      await sharedPreferences.remove('profileMediaPath');
      await sharedPreferences.remove('profileMediaOriginalName');
      await sharedPreferences.remove('profileMediaSizeBytes');
      await sharedPreferences.remove('profileMediaKind');
      await sharedPreferences.remove('profileMediaScale');
      await sharedPreferences.remove('profileMediaAlignmentX');
      await sharedPreferences.remove('profileMediaAlignmentY');
    }
    // Removed profile/savings fields are explicitly purged so old backups or
    // cloud preference payloads cannot bring the retired feature back.
    final legacyProfilePrefs = await prefs.prefs;
    for (final key in const [
      'profileBio',
      'savingsSuggestionProfile',
      'savedSavingsIdeas',
      'plannedSavingsIdeas',
      'seenSavingsSuggestionKeys',
    ]) {
      await legacyProfilePrefs.remove(key);
    }
    dismissedFinancialHealthSummaryKeys = await prefs.getStringList('dismissedFinancialHealthSummaryKeys');
    dateRangeType = await prefs.getEnum('dateRangeType', DateRangeType.values, DateRangeType.thisMonth);
    final startRaw = await prefs.getString('customStart', '');
    final endRaw = await prefs.getString('customEnd', '');
    customStart = startRaw.isEmpty ? null : DateTime.tryParse(startRaw);
    customEnd = endRaw.isEmpty ? null : DateTime.tryParse(endRaw);
    filterAccountIds = await prefs.getStringList('filterAccountIds');
    filterCategoryIds = await prefs.getStringList('filterCategoryIds');
    filterTypes = (await prefs.getStringList('filterTypes')).map((e) => enumByName(MoneyTransactionType.values, e, MoneyTransactionType.expense)).toList();
    defaultAccountId = await prefs.getString('defaultAccountId', '');
    if (defaultAccountId?.isEmpty == true) defaultAccountId = null;
    defaultExpenseCategoryId = await prefs.getString('defaultExpenseCategoryId', '');
    if (defaultExpenseCategoryId?.isEmpty == true) defaultExpenseCategoryId = null;
    defaultIncomeCategoryId = await prefs.getString('defaultIncomeCategoryId', '');
    if (defaultIncomeCategoryId?.isEmpty == true) defaultIncomeCategoryId = null;
    compactHomeSummary = await prefs.getBool('compactHomeSummary', false);
    automaticUpdatePopupEnabled = await prefs.getBool('automaticUpdatePopupEnabled', true);
    final sharedPreferences = await prefs.prefs;
    await sharedPreferences.remove('reducedMotion');
    reminderEnabled = await prefs.getBool('reminderEnabled', false);
    final hour = await prefs.getInt('reminderHour', 21);
    final minute = await prefs.getInt('reminderMinute', 0);
    reminderTime = TimeOfDay(hour: hour, minute: minute);
    loanRecordTransactionsByDefault = await prefs.getBool('loanRecordTransactionsByDefault', true);
    loanRemindersEnabled = await prefs.getBool('loanRemindersEnabled', true);
    loanShowWrittenOff = await prefs.getBool('loanShowWrittenOff', false);
    loanTransactionsVisibleInTransactionList = await prefs.getBool('loanTransactionsVisibleInTransactionList', true);
    cloudSyncEnabled = await prefs.getBool('cloudSyncEnabled', false);
    syncDatabaseProvider = await prefs.getEnum('syncDatabaseProvider', SyncDatabaseProvider.values, SyncDatabaseProvider.mongoDb);
    if (!userSyncDatabaseProviders.contains(syncDatabaseProvider)) {
      syncDatabaseProvider = SyncDatabaseProvider.mongoDb;
      cloudSyncEnabled = false;
      await prefs.setEnum('syncDatabaseProvider', SyncDatabaseProvider.mongoDb);
      await prefs.setBool('cloudSyncEnabled', false);
    }
    // Account sync is self-hosted only. Migrate the URL from releases that
    // stored it as the "custom" endpoint. Sessions that belonged to the
    // legacy non-self-hosted endpoint are cleared below without touching finance data.
    final syncPrefs = await prefs.prefs;
    final hadLegacyCustomSyncFlag = syncPrefs.containsKey('useCustomCloudSync');
    final legacyUsedSelfHostedSync = hadLegacyCustomSyncFlag && await prefs.getBool('useCustomCloudSync', false);
    final legacySelfHostedUrl = CloudSyncService.normalizeApiBaseUrl(
      await prefs.getString('customCloudSyncApiBaseUrl', ''),
    );
    selfHostedSyncApiBaseUrl = CloudSyncService.normalizeApiBaseUrl(
      await prefs.getString('selfHostedSyncApiBaseUrl', legacyUsedSelfHostedSync ? legacySelfHostedUrl : ''),
    );
    cloudSyncApiBaseUrl = selfHostedSyncApiBaseUrl;
    await prefs.setString('selfHostedSyncApiBaseUrl', selfHostedSyncApiBaseUrl);
    await syncPrefs.remove('useCustomCloudSync');
    await syncPrefs.remove('customCloudSyncApiBaseUrl');
    cloudSyncId = await prefs.getString('cloudSyncId', '');
    cloudSyncPin = await secureCredentials.readCloudSyncPin();
    final legacyPin = await prefs.getString('cloudSyncPin', '');
    if (cloudSyncPin.isEmpty && legacyPin.trim().isNotEmpty) {
      cloudSyncPin = legacyPin.trim();
      await secureCredentials.writeCloudSyncPin(cloudSyncPin);
      await (await prefs.prefs).remove('cloudSyncPin');
    }
    syncMongoDbUrl = await secureCredentials.readMongoDbUrl();
    syncMongoDatabaseName = MongoDbSyncService.normalizeDatabaseName(await prefs.getString('syncMongoDatabaseName', MongoDbSyncService.defaultDatabaseName));
    syncMongoCollectionName = MongoDbSyncService.normalizeCollectionName(await prefs.getString('syncMongoCollectionName', MongoDbSyncService.defaultCollectionName));
    syncMongoSyncId = CloudSyncService.normalizeSyncId(await prefs.getString('syncMongoSyncId', ''));
    syncMongoSyncPin = await secureCredentials.readMongoDbSyncPin();
    syncTursoDatabaseUrl = await prefs.getString('syncTursoDatabaseUrl', '');
    syncTursoAuthToken = await secureCredentials.readTursoAuthToken();
    syncAccountUsername = await prefs.getString('syncAccountUsername', '');
    if (syncAccountUsername.trim().isEmpty) {
      final legacyEmail = await prefs.getString('syncAccountEmail', '');
      syncAccountUsername = _legacyUsernameFromEmail(legacyEmail);
      if (syncAccountUsername.isNotEmpty) {
        await prefs.setString('syncAccountUsername', syncAccountUsername);
      }
      await (await prefs.prefs).remove('syncAccountEmail');
    }
    syncDeviceId = await prefs.getString('syncDeviceId', '');
    if (syncDeviceId.trim().isEmpty) {
      syncDeviceId = _uuid.v4();
      await prefs.setString('syncDeviceId', syncDeviceId);
    }
    syncAccessToken = await secureCredentials.readAccessToken();
    syncRefreshToken = await secureCredentials.readRefreshToken();
    if (hadLegacyCustomSyncFlag && !legacyUsedSelfHostedSync && (syncAccessToken.isNotEmpty || syncRefreshToken.isNotEmpty)) {
      await secureCredentials.clearAccountTokens();
      syncAccessToken = '';
      syncRefreshToken = '';
      syncAccountUsername = '';
      await prefs.setString('syncAccountUsername', '');
      await prefs.setBool('cloudSyncEnabled', false);
      await database.resetLocalSyncTracking();
      await database.writeSyncState('serverCursor', '0');
    }
    cloudSyncEnabled = syncAccessToken.isNotEmpty && syncRefreshToken.isNotEmpty && selfHostedSyncApiBaseUrl.isNotEmpty;
    final lastSyncRaw = await prefs.getString('cloudSyncLastAt', '');
    cloudSyncLastAt = lastSyncRaw.isEmpty ? null : DateTime.tryParse(lastSyncRaw);
    cloudSyncPending = await prefs.getBool('cloudSyncPending', false);
    authoritativeCloudUploadPending = await prefs.getBool('authoritativeCloudUploadPending', false);
    newSyncAccountAwaitingSetupChoice = await prefs.getBool('newSyncAccountAwaitingSetupChoice', false);
    syncStatus = cloudSyncEnabled ? cloudSyncStatusText : 'Offline';
    pendingAndroidUpdatePath = await prefs.getString('pendingAndroidUpdatePath', '');
    pendingAndroidUpdateVersion = await prefs.getString('pendingAndroidUpdateVersion', '');
    final pendingKindName = await prefs.getString('pendingAndroidUpdateKind', '');
    pendingAndroidUpdateKind = pendingKindName.isEmpty ? null : enumByName(UpdateAssetKind.values, pendingKindName, UpdateAssetKind.arm64);
    if (pendingAndroidUpdatePath.isNotEmpty && _isPendingAndroidUpdateAlreadyInstalled()) {
      await _clearPendingAndroidUpdate(deleteFile: true);
    } else if (pendingAndroidUpdatePath.isNotEmpty && !await File(pendingAndroidUpdatePath).exists()) {
      await _clearPendingAndroidUpdate();
    }
    pendingWindowsUpdatePath = await prefs.getString('pendingWindowsUpdatePath', '');
    pendingWindowsUpdateVersion = await prefs.getString('pendingWindowsUpdateVersion', '');
    if (pendingWindowsUpdatePath.isNotEmpty && _isPendingWindowsUpdateAlreadyInstalled()) {
      await _clearPendingWindowsUpdate(deleteFile: true);
    } else if (pendingWindowsUpdatePath.isNotEmpty && !await File(pendingWindowsUpdatePath).exists()) {
      await _clearPendingWindowsUpdate();
    }
    lastSafetyBackupPath = await prefs.getString('lastSafetyBackupPath', '');
    final safetyAtRaw = await prefs.getString('lastSafetyBackupAt', '');
    lastSafetyBackupAt = safetyAtRaw.isEmpty ? null : DateTime.tryParse(safetyAtRaw);
    if (lastSafetyBackupPath.isNotEmpty && !await File(lastSafetyBackupPath).exists()) {
      lastSafetyBackupPath = '';
      lastSafetyBackupAt = null;
      await prefs.setString('lastSafetyBackupPath', '');
      await prefs.setString('lastSafetyBackupAt', '');
    }
    autoBackupEnabled = await prefs.getBool('autoBackupEnabled', false);
    autoBackupFrequency = await prefs.getEnum('autoBackupFrequency', AutoBackupFrequency.values, AutoBackupFrequency.daily);
    autoBackupHour = (await prefs.getInt('autoBackupHour', 2)).clamp(0, 23).toInt();
    autoBackupMinute = (await prefs.getInt('autoBackupMinute', 0)).clamp(0, 59).toInt();
    autoBackupWeekday = (await prefs.getInt('autoBackupWeekday', DateTime.sunday)).clamp(DateTime.monday, DateTime.sunday).toInt();
    autoBackupMonthDay = (await prefs.getInt('autoBackupMonthDay', 1)).clamp(1, 28).toInt();
    autoBackupDeleteOlder = await prefs.getBool('autoBackupDeleteOlder', true);
    autoBackupDirectoryPath = await prefs.getString('autoBackupDirectoryPath', '');
    autoBackupDirectoryUri = await prefs.getString('autoBackupDirectoryUri', '');
    autoBackupDirectoryLabel = await prefs.getString('autoBackupDirectoryLabel', '');
    if (Platform.isAndroid &&
        autoBackupDirectoryUri.trim().isNotEmpty &&
        autoBackupDirectoryLabel.trim().isNotEmpty) {
      final normalizedBackupLabel = autoBackupDirectoryLabel.replaceAll('\\', '/').toLowerCase();
      if (normalizedBackupLabel == 'koinly/backup' || normalizedBackupLabel.endsWith('/koinly/backup')) {
        // Already points at the dedicated destination.
      } else if (normalizedBackupLabel == 'koinly' || normalizedBackupLabel.endsWith('/koinly')) {
        autoBackupDirectoryLabel = '${autoBackupDirectoryLabel.trim()}/Backup';
      } else {
        autoBackupDirectoryLabel = '${autoBackupDirectoryLabel.trim()}/Koinly/Backup';
      }
    }
    lastAutoBackupPath = await prefs.getString('lastAutoBackupPath', '');
    final autoBackupAtRaw = await prefs.getString('lastAutoBackupAt', '');
    lastAutoBackupAt = autoBackupAtRaw.isEmpty ? null : DateTime.tryParse(autoBackupAtRaw);
    autoBackupError = null;
    if (Platform.isAndroid && autoBackupDirectoryUri.trim().isEmpty && autoBackupDirectoryPath.trim().isNotEmpty) {
      // Raw /storage/... paths are not writable under Android scoped storage.
      // Keep automatic backup enabled, but require the user to re-select the
      // folder once through Storage Access Framework so the grant persists.
      autoBackupError = 'Choose the backup folder again once to grant Android folder access.';
    }
  }

  String get lastSafetyBackupLabel {
    if (lastSafetyBackupAt == null) return 'No safety backup yet';
    return 'Last saved ${DateFormat('MMM d, yyyy • h:mm a').format(lastSafetyBackupAt!.toLocal())}';
  }

  bool get hasLastSafetyBackup => lastSafetyBackupPath.isNotEmpty && File(lastSafetyBackupPath).existsSync();

  Future<File?> createSafetyBackup(String reason) async {
    try {
      final file = await BackupService.createSafetyBackup(this, reason: reason);
      lastSafetyBackupPath = file.path;
      lastSafetyBackupAt = DateTime.now();
      await prefs.setString('lastSafetyBackupPath', lastSafetyBackupPath);
      await prefs.setString('lastSafetyBackupAt', lastSafetyBackupAt!.toIso8601String());
      notifyListeners();
      return file;
    } catch (_) {
      return null;
    }
  }

  Future<void> requireSafetyBackup(String reason) async {
    final file = await createSafetyBackup(reason);
    if (file == null) {
      throw StateError('Could not create a safety backup before changing local data.');
    }
  }

  Future<bool> restoreLastSafetyBackup() async {
    if (!hasLastSafetyBackup) return false;
    await BackupService.restoreBackupFile(this, File(lastSafetyBackupPath));
    await markRestoredDataForCloudUpload();
    return true;
  }

  TimeOfDay get autoBackupTime => TimeOfDay(hour: autoBackupHour, minute: autoBackupMinute);

  String get autoBackupFrequencyLabel => switch (autoBackupFrequency) {
        AutoBackupFrequency.daily => 'Daily',
        AutoBackupFrequency.weekly => 'Weekly',
        AutoBackupFrequency.monthly => 'Monthly',
      };

  String get autoBackupLocationLabel {
    if (Platform.isAndroid && autoBackupDirectoryUri.trim().isNotEmpty) {
      return autoBackupDirectoryLabel.trim().isEmpty ? 'Koinly/Backup' : autoBackupDirectoryLabel.trim();
    }
    if (autoBackupDirectoryPath.trim().isEmpty) return 'Choose folder';
    final normalized = p.normalize(autoBackupDirectoryPath.trim());
    final parent = p.basename(p.dirname(normalized));
    final name = p.basename(normalized);
    return parent.isEmpty ? name : '$parent/$name';
  }

  String get automaticBackupSettingsSummary {
    if (!autoBackupEnabled) return 'Off';
    final when = DateFormat('h:mm a').format(DateTime(2000, 1, 1, autoBackupHour, autoBackupMinute));
    final history = autoBackupDeleteOlder ? 'latest only' : 'keep history';
    return '$autoBackupFrequencyLabel at $when • $history • $autoBackupLocationLabel';
  }

  String get lastAutoBackupLabel {
    if (lastAutoBackupAt == null) return 'No automatic backup yet';
    return 'Last saved ${DateFormat('MMM d, yyyy • h:mm a').format(lastAutoBackupAt!.toLocal())}';
  }

  String get nextAutoBackupLabel {
    if (!autoBackupEnabled) return 'Automatic backup is off';
    if (automaticBackupDue) return 'Backup due now';
    final next = _nextAutoBackupSlot(DateTime.now());
    return 'Next ${DateFormat('MMM d, yyyy • h:mm a').format(next)}';
  }

  DateTime _mostRecentAutoBackupSlot(DateTime now) {
    DateTime atTime(DateTime day) => DateTime(day.year, day.month, day.day, autoBackupHour, autoBackupMinute);
    switch (autoBackupFrequency) {
      case AutoBackupFrequency.daily:
        var target = atTime(now);
        if (target.isAfter(now)) target = target.subtract(const Duration(days: 1));
        return target;
      case AutoBackupFrequency.weekly:
        final daysBack = (now.weekday - autoBackupWeekday + 7) % 7;
        var day = DateTime(now.year, now.month, now.day).subtract(Duration(days: daysBack));
        var target = atTime(day);
        if (target.isAfter(now)) {
          day = day.subtract(const Duration(days: 7));
          target = atTime(day);
        }
        return target;
      case AutoBackupFrequency.monthly:
        var target = DateTime(now.year, now.month, autoBackupMonthDay, autoBackupHour, autoBackupMinute);
        if (target.isAfter(now)) {
          target = DateTime(now.year, now.month - 1, autoBackupMonthDay, autoBackupHour, autoBackupMinute);
        }
        return target;
    }
  }

  DateTime _nextAutoBackupSlot(DateTime now) {
    final latest = _mostRecentAutoBackupSlot(now);
    return switch (autoBackupFrequency) {
      AutoBackupFrequency.daily => latest.add(const Duration(days: 1)),
      AutoBackupFrequency.weekly => latest.add(const Duration(days: 7)),
      AutoBackupFrequency.monthly => DateTime(latest.year, latest.month + 1, autoBackupMonthDay, autoBackupHour, autoBackupMinute),
    };
  }

  bool get automaticBackupDue {
    if (!autoBackupEnabled) return false;
    final latestSlot = _mostRecentAutoBackupSlot(DateTime.now());
    return lastAutoBackupAt == null || lastAutoBackupAt!.isBefore(latestSlot);
  }

  void _scheduleAutomaticBackupTimer() {
    _autoBackupTimer?.cancel();
    _autoBackupTimer = null;
    if (!autoBackupEnabled || loading) return;
    final now = DateTime.now();
    final next = _nextAutoBackupSlot(now);
    var delay = next.difference(now);
    if (delay.isNegative) delay = const Duration(seconds: 1);
    _autoBackupTimer = Timer(delay + const Duration(seconds: 1), () {
      unawaited(runAutomaticBackupIfDue());
    });
  }

  Future<String?> runAutomaticBackupIfDue({bool force = false}) async {
    if ((!autoBackupEnabled && !force) || _autoBackupInFlight || loading) return null;
    if (!force && !automaticBackupDue) {
      _scheduleAutomaticBackupTimer();
      return null;
    }
    _autoBackupInFlight = true;
    try {
      final location = await BackupService.createAutomaticBackup(
        this,
        directoryPath: autoBackupDirectoryPath,
        directoryUri: autoBackupDirectoryUri,
        directoryLabel: autoBackupDirectoryLabel,
        deleteOlderBackups: autoBackupDeleteOlder,
      );
      lastAutoBackupPath = location;
      lastAutoBackupAt = DateTime.now();
      autoBackupError = null;
      await prefs.setString('lastAutoBackupPath', lastAutoBackupPath);
      await prefs.setString('lastAutoBackupAt', lastAutoBackupAt!.toIso8601String());
      notifyListeners();
      return location;
    } catch (error) {
      final text = error is PlatformException ? (error.message ?? error.code) : error.toString();
      autoBackupError = text
          .replaceFirst('FileSystemException: ', '')
          .replaceFirst('Bad state: ', '')
          .trim();
      notifyListeners();
      return null;
    } finally {
      _autoBackupInFlight = false;
      _scheduleAutomaticBackupTimer();
    }
  }

  Future<void> setAutomaticBackupSettings({
    required bool enabled,
    required AutoBackupFrequency frequency,
    required TimeOfDay time,
    required int weekday,
    required int monthDay,
    required bool deleteOlderBackups,
    required String directoryPath,
    required String directoryUri,
    required String directoryLabel,
  }) async {
    final normalizedDirectory = directoryPath.trim();
    final normalizedUri = directoryUri.trim();
    final normalizedLabel = directoryLabel.trim();
    final shouldSeedBackup = enabled &&
        (!autoBackupEnabled ||
            normalizedDirectory != autoBackupDirectoryPath.trim() ||
            normalizedUri != autoBackupDirectoryUri.trim());
    autoBackupEnabled = enabled;
    autoBackupFrequency = frequency;
    autoBackupHour = time.hour.clamp(0, 23).toInt();
    autoBackupMinute = time.minute.clamp(0, 59).toInt();
    autoBackupWeekday = weekday.clamp(DateTime.monday, DateTime.sunday).toInt();
    autoBackupMonthDay = monthDay.clamp(1, 28).toInt();
    autoBackupDeleteOlder = deleteOlderBackups;
    autoBackupDirectoryPath = normalizedDirectory;
    autoBackupDirectoryUri = normalizedUri;
    autoBackupDirectoryLabel = normalizedLabel;
    autoBackupError = null;
    await prefs.setBool('autoBackupEnabled', autoBackupEnabled);
    await prefs.setEnum('autoBackupFrequency', autoBackupFrequency);
    await prefs.setInt('autoBackupHour', autoBackupHour);
    await prefs.setInt('autoBackupMinute', autoBackupMinute);
    await prefs.setInt('autoBackupWeekday', autoBackupWeekday);
    await prefs.setInt('autoBackupMonthDay', autoBackupMonthDay);
    await prefs.setBool('autoBackupDeleteOlder', autoBackupDeleteOlder);
    await prefs.setString('autoBackupDirectoryPath', autoBackupDirectoryPath);
    await prefs.setString('autoBackupDirectoryUri', autoBackupDirectoryUri);
    await prefs.setString('autoBackupDirectoryLabel', autoBackupDirectoryLabel);
    notifyListeners();
    if (autoBackupEnabled) {
      await runAutomaticBackupIfDue(force: shouldSeedBackup);
    } else {
      _autoBackupTimer?.cancel();
      _autoBackupTimer = null;
    }
  }

  Future<DataHealthReport> checkDataHealth() async {
    dataHealthBusy = true;
    notifyListeners();
    try {
      final items = <DataHealthItem>[];
      final accountIds = accounts.map((account) => account.id).toSet();
      final categoryIds = categories.map((category) => category.id).toSet();
      final loanContactIds = loanContacts.map((contact) => contact.id).toSet();
      final loanIds = loans.map((loan) => loan.id).toSet();

      var missingAccountReferences = 0;
      var missingCategoryReferences = 0;
      for (final tx in transactions) {
        if (tx.fromAccountId.isEmpty || !accountIds.contains(tx.fromAccountId)) {
          missingAccountReferences += 1;
        }
        if (tx.type == MoneyTransactionType.transfer && (tx.toAccountId == null || !accountIds.contains(tx.toAccountId))) {
          missingAccountReferences += 1;
        }
        if (tx.type != MoneyTransactionType.transfer && tx.categoryId.isNotEmpty && !categoryIds.contains(tx.categoryId)) {
          missingCategoryReferences += 1;
        }
      }

      var invalidBudgetScopes = 0;
      for (final budget in budgets) {
        if (!budget.allAccountsSelected && budget.accountIds.any((id) => !accountIds.contains(id))) {
          invalidBudgetScopes += 1;
        }
        if (!budget.allCategoriesSelected && budget.categoryIds.any((id) => !categoryIds.contains(id))) {
          invalidBudgetScopes += 1;
        }
      }

      final missingLoanContacts = loans.where((loan) => !loanContactIds.contains(loan.contactId)).length;
      final missingPaymentLoans = loanPayments.where((payment) => !loanIds.contains(payment.loanId)).length;
      final inconsistentPaymentSplits = loanPayments
          .where((payment) => (payment.amount - payment.interestComponent - payment.principalComponent).abs() >= 0.005)
          .length;
      final severelyOverdueLoans = loans.where((loan) => computationFor(loan.id).daysOverdue > 30).length;

      final pendingSyncOperations = await database.pendingSyncOperationCount();
      // Older builds left resolved conflict rows open. A conflict older than the
      // last completed sync is safe to close when that entity has no remaining
      // outbox work; conflicts created after the last successful sync stay open.
      if (cloudSyncLastAt != null) {
        await database.resolveSettledSyncConflicts(
          settledThrough: cloudSyncLastAt!.millisecondsSinceEpoch,
        );
      }
      final openSyncConflicts = await database.openSyncConflictCount();
      final skippedStarterPlaceholdersVisible = starterAccountsSkipped && await database.hasOnlyUntouchedStarterAccounts();

      if (accounts.isEmpty) {
        items.add(const DataHealthItem(
          severity: DataHealthSeverity.info,
          title: 'No accounts yet',
          body: 'This is okay for offline-first use. Add an account when you want to start tracking balances.',
        ));
      }
      if (categories.isEmpty) {
        items.add(const DataHealthItem(
          severity: DataHealthSeverity.warning,
          title: 'No visible categories',
          body: 'Transactions need income or expense categories for clean reports and breakdowns.',
        ));
      }
      if (missingAccountReferences > 0) {
        items.add(DataHealthItem(
          severity: DataHealthSeverity.error,
          title: 'Broken account references',
          body: '$missingAccountReferences transaction account reference${missingAccountReferences == 1 ? '' : 's'} point to missing accounts.',
        ));
      }
      if (missingCategoryReferences > 0) {
        items.add(DataHealthItem(
          severity: DataHealthSeverity.warning,
          title: 'Missing transaction categories',
          body: '$missingCategoryReferences transaction${missingCategoryReferences == 1 ? '' : 's'} point to categories that no longer exist.',
        ));
      }
      if (invalidBudgetScopes > 0) {
        items.add(DataHealthItem(
          severity: DataHealthSeverity.warning,
          title: 'Budget scope needs review',
          body: '$invalidBudgetScopes budget account/category selection${invalidBudgetScopes == 1 ? '' : 's'} include missing records.',
        ));
      }
      if (missingLoanContacts > 0) {
        items.add(DataHealthItem(
          severity: DataHealthSeverity.error,
          title: 'Missing people',
          body: '$missingLoanContacts record${missingLoanContacts == 1 ? '' : 's'} point to a person that no longer exists.',
        ));
      }
      if (missingPaymentLoans > 0) {
        items.add(DataHealthItem(
          severity: DataHealthSeverity.error,
          title: 'Orphaned repayments',
          body: '$missingPaymentLoans repayment${missingPaymentLoans == 1 ? '' : 's'} point to a missing record.',
        ));
      }
      if (inconsistentPaymentSplits > 0) {
        items.add(DataHealthItem(
          severity: DataHealthSeverity.warning,
          title: 'Repayment split mismatch',
          body: '$inconsistentPaymentSplits repayment${inconsistentPaymentSplits == 1 ? '' : 's'} have inconsistent interest and principal amounts.',
        ));
      }
      if (severelyOverdueLoans > 0) {
        items.add(DataHealthItem(
          severity: DataHealthSeverity.warning,
          title: 'Long-overdue records',
          body: '$severelyOverdueLoans active record${severelyOverdueLoans == 1 ? ' is' : 's are'} more than 30 days overdue.',
        ));
      }
      if (openSyncConflicts > 0) {
        items.add(DataHealthItem(
          severity: DataHealthSeverity.error,
          title: 'Sync conflicts pending',
          body: '$openSyncConflicts cloud sync conflict${openSyncConflicts == 1 ? '' : 's'} need attention before every device can fully agree.',
        ));
      }
      if (pendingSyncOperations > 0) {
        items.add(DataHealthItem(
          severity: DataHealthSeverity.info,
          title: 'Cloud upload backlog',
          body: '$pendingSyncOperations local change${pendingSyncOperations == 1 ? '' : 's'} are waiting to sync when the backend is reachable.',
        ));
      }
      if (skippedStarterPlaceholdersVisible) {
        items.add(const DataHealthItem(
          severity: DataHealthSeverity.warning,
          title: 'Skipped starter accounts are still visible',
          body: 'The setup skip flag is saved, but untouched Cash/Card/Bank Account placeholders are still in local data.',
          actionLabel: 'Remove starter accounts',
        ));
      }

      final report = DataHealthReport(
        checkedAt: DateTime.now(),
        items: List.unmodifiable(items),
        accountCount: accounts.length,
        categoryCount: categories.length,
        transactionCount: transactions.length,
        budgetCount: budgets.length,
        loanCount: loans.length,
        loanPaymentCount: loanPayments.length,
        pendingSyncOperations: pendingSyncOperations,
        openSyncConflicts: openSyncConflicts,
        skippedStarterPlaceholdersVisible: skippedStarterPlaceholdersVisible,
      );
      dataHealthReport = report;
      return report;
    } finally {
      dataHealthBusy = false;
      notifyListeners();
    }
  }

  Future<void> removeSkippedStarterAccountsFromHealthCheck() async {
    final deletedStarterAccountIds = await database.deleteUntouchedStarterAccounts();
    for (final accountId in deletedStarterAccountIds) {
      await database.enqueueDelete('accounts', accountId);
    }
    await reload(queueSync: deletedStarterAccountIds.isNotEmpty);
    await checkDataHealth();
  }

  String _maskedSyncUsername() {
    final trimmed = syncAccountUsername.trim();
    if (trimmed.isEmpty) return 'Not signed in';
    if (trimmed.length <= 2) return '${trimmed.substring(0, 1)}*';
    return '${trimmed.substring(0, 2)}***';
  }

  Future<String> buildDiagnosticsReport() async {
    final report = await checkDataHealth();
    final buffer = StringBuffer()
      ..writeln('Koinly diagnostics')
      ..writeln('Generated: ${DateTime.now().toIso8601String()}')
      ..writeln('Installed version: $appVersion')
      ..writeln('Platform: ${_platformName()}')
      ..writeln('')
      ..writeln('Setup')
      ..writeln('- Onboarding completed: $onboardingCompleted')
      ..writeln('- Current platform setup completed: $setupCompletedForCurrentPlatform')
      ..writeln('- Starter accounts skipped: $starterAccountsSkipped')
      ..writeln('- Low-end friendly UI: $kLowEndFriendlyUi')
      ..writeln('')
      ..writeln('Local data')
      ..writeln('- Accounts: ${report.accountCount}')
      ..writeln('- Visible categories: ${report.categoryCount}')
      ..writeln('- Transactions: ${report.transactionCount}')
      ..writeln('- Budgets: ${report.budgetCount}')
      ..writeln('- Lending and borrowing records: ${report.loanCount}')
      ..writeln('- Repayments: ${report.loanPaymentCount}')
      ..writeln('- Last safety backup: ${lastSafetyBackupAt?.toIso8601String() ?? 'none'}')
      ..writeln('')
      ..writeln('Sync')
      ..writeln('- Self-hosted Worker configured: ${selfHostedSyncApiBaseUrl.isNotEmpty}')
      ..writeln('- Signed in: $cloudSyncEnabled')
      ..writeln('- Account: ${_maskedSyncUsername()}')
      ..writeln('- New account setup choice pending: $newSyncAccountAwaitingSetupChoice')
      ..writeln('- Status: $syncStatus')
      ..writeln('- Pending upload operations: ${report.pendingSyncOperations}')
      ..writeln('- Open sync conflicts: ${report.openSyncConflicts}')
      ..writeln('- Last successful sync: ${cloudSyncLastAt?.toIso8601String() ?? 'none'}')
      ..writeln('- Sync pending retry: $cloudSyncPending');
    if (cloudSyncError != null && cloudSyncError!.trim().isNotEmpty) {
      buffer.writeln('- Last sync error: ${redactSyncSecrets(cloudSyncError!)}');
    }
    buffer
      ..writeln('')
      ..writeln('Updates')
      ..writeln('- Repository: $updateRepositorySlug')
      ..writeln('- Update status: $updateStatusMessage')
      ..writeln('- Automatic update pop-ups: ${automaticUpdatePopupEnabled ? 'on' : 'off'}')
      ..writeln('- Latest release: ${latestGithubRelease?.displayVersion ?? 'not checked'}')
      ..writeln('- Pending Android APK: ${pendingAndroidUpdatePath.isNotEmpty ? pendingAndroidUpdateVersion : 'none'}')
      ..writeln('')
      ..writeln('Health findings');
    if (report.items.isEmpty) {
      buffer.writeln('- Healthy: no findings');
    } else {
      for (final item in report.items) {
        buffer.writeln('- ${enumName(item.severity)}: ${item.title} — ${item.body}');
      }
    }
    return buffer.toString();
  }

  Future<Map<String, dynamic>> exportPreferences() async => {
        'themePreference': enumName(themePreference),
        'currencySymbol': currencySymbol,
        'currencyCode': currencyCode,
        'currencyPosition': enumName(currencyPosition),
        'useSeparators': useSeparators,
        'amountsHidden': amountsHidden,
        'profileDisplayName': profileDisplayName,
        'dismissedFinancialHealthSummaryKeys': dismissedFinancialHealthSummaryKeys,
        'dateRangeType': enumName(dateRangeType),
        'customStart': customStart?.toIso8601String() ?? '',
        'customEnd': customEnd?.toIso8601String() ?? '',
        'filterAccountIds': filterAccountIds,
        'filterCategoryIds': filterCategoryIds,
        'filterTypes': filterTypes.map(enumName).toList(),
        'defaultAccountId': defaultAccountId ?? '',
        'defaultExpenseCategoryId': defaultExpenseCategoryId ?? '',
        'defaultIncomeCategoryId': defaultIncomeCategoryId ?? '',
        'compactHomeSummary': compactHomeSummary,
        'reminderEnabled': reminderEnabled,
        'reminderHour': reminderTime.hour,
        'reminderMinute': reminderTime.minute,
        'loanRecordTransactionsByDefault': loanRecordTransactionsByDefault,
        'loanRemindersEnabled': loanRemindersEnabled,
        'loanShowWrittenOff': loanShowWrittenOff,
        'loanTransactionsVisibleInTransactionList': loanTransactionsVisibleInTransactionList,
        'syncDatabaseProvider': enumName(syncDatabaseProvider),
        'syncMongoDatabaseName': syncMongoDatabaseName,
        'syncMongoCollectionName': syncMongoCollectionName,
      };

  Future<void> importPreferences(Map<String, dynamic> data) async {
    final sp = await prefs.prefs;
    const deviceLocalKeys = {
      'onboardingCompleted',
      'starterAccountsSkipped',
      'reducedMotion',
      'desktopSetupVersionCompleted',
      'cloudSyncEnabled',
      'cloudSyncPending',
      'authoritativeCloudUploadPending',
      'newSyncAccountAwaitingSetupChoice',
      'cloudSyncLastAt',
      'automaticUpdatePopupEnabled',
      'cloudSyncApiBaseUrl',
      'selfHostedSyncApiBaseUrl',
      'useCustomCloudSync', // legacy, ignored if an old backup contains it
      'customCloudSyncApiBaseUrl', // legacy, ignored if an old backup contains it
      'cloudSyncId',
      'cloudSyncPin',
      'syncAccountUsername',
      'syncDeviceId',
      'profileMediaPath',
      'profileMediaOriginalName',
      'profileMediaKind',
      'profileMediaSizeBytes',
      'profileMediaPermissionPrompted',
      'profileMediaScale',
      'profileMediaAlignmentX',
      'profileMediaAlignmentY',
      // Retired preferences are ignored if they arrive from an older backup or
      // another device running a pre-1.0.1070 build.
      'profileBio',
      'savingsSuggestionProfile',
      'savedSavingsIdeas',
      'plannedSavingsIdeas',
      'seenSavingsSuggestionKeys',
    };
    for (final entry in data.entries) {
      if (deviceLocalKeys.contains(entry.key)) continue;
      final value = entry.value;
      if (value is bool) await sp.setBool(entry.key, value);
      if (value is int) await sp.setInt(entry.key, value);
      if (value is String) await sp.setString(entry.key, value);
      if (value is List) await sp.setStringList(entry.key, value.map((e) => '$e').toList());
    }
    await _loadPreferences();
  }

  Future<void> mergeRemotePreferences(Map<String, dynamic> incoming) async {
    final current = await exportPreferences();
    await importPreferences(mergeFinancePreferences(current, incoming, CategoryMergePlan.empty));
  }

  Future<Map<String, dynamic>> exportCloudPayload() async {
    final normalized = normalizeCategoryDatabasePayload(await database.exportAll());
    return {
      'version': CloudSyncService.payloadVersion,
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'database': normalized.database,
      'preferences': remapCategoryPreferences(await exportPreferences(), normalized.plan),
    };
  }

  String get cloudSyncStatusText {
    if (cloudSyncBusy) return syncStatus.trim().isEmpty ? 'Online sync • Syncing...' : syncStatus;
    if (newSyncAccountAwaitingSetupChoice) return 'Account created • Setup choice required';
    if (authoritativeCloudUploadPending) return 'Restore merge pending';
    if (cloudSyncPending) return 'Sync pending • Waiting for internet';
    if (cloudSyncErrorCode == 'SYNC_APPROVAL_REQUIRED') return 'Online sync • Admin approval required';
    if (cloudSyncError != null && cloudSyncError!.trim().isNotEmpty) return 'Sync error • $cloudSyncError';
    if (!cloudSyncEnabled) return 'Sign in required';
    if (cloudSyncLastAt == null) return 'Signed in • Not synced yet';
    return 'Synced • ${DateFormat('yyyy-MM-dd HH:mm').format(cloudSyncLastAt!.toLocal())}';
  }

  bool get cloudSyncApprovalRequired => cloudSyncErrorCode == 'SYNC_APPROVAL_REQUIRED';

  bool get hasAvailableUpdate => updateCheckOutcome == UpdateCheckOutcome.updateAvailable && latestGithubRelease != null;
  bool get hasPendingAndroidUpdate => pendingAndroidUpdatePath.isNotEmpty && pendingAndroidUpdateVersion.isNotEmpty && !_isPendingAndroidUpdateAlreadyInstalled();
  bool get hasPendingWindowsUpdate => pendingWindowsUpdatePath.isNotEmpty && pendingWindowsUpdateVersion.isNotEmpty && !_isPendingWindowsUpdateAlreadyInstalled();

  Map<UpdateAssetKind, ReleaseAsset> get availableAndroidUpdateAssets {
    final release = latestGithubRelease;
    if (release == null) return const {};
    return ReleaseAssetMatcher.androidApks(release);
  }

  ReleaseAsset? get selectedAndroidUpdateAsset => availableAndroidUpdateAssets[selectedAndroidUpdateKind] ?? availableAndroidUpdateAssets[UpdateAssetKind.universal];

  ReleaseAsset? get windowsUpdateInstallerAsset {
    final release = latestGithubRelease;
    if (release == null) return null;
    return ReleaseAssetMatcher.preferredWindowsInstaller(release);
  }

  bool canShowStartupUpdateDialog(GithubRelease release) => _shownUpdateDialogVersionThisSession != release.displayVersion;

  void markStartupUpdateDialogShown(GithubRelease release) {
    _shownUpdateDialogVersionThisSession = release.displayVersion;
  }

  void selectAndroidUpdateKind(UpdateAssetKind kind) {
    selectedAndroidUpdateKind = kind;
    notifyListeners();
  }

  Future<void> setAutomaticUpdatePopupEnabled(bool enabled) async {
    if (automaticUpdatePopupEnabled == enabled) return;
    automaticUpdatePopupEnabled = enabled;
    await prefs.setBool('automaticUpdatePopupEnabled', enabled);
    await UpdateBackgroundService.setEnabled(enabled);
    notifyListeners();
  }

  Future<UpdateCheckResult> checkForUpdates({bool manual = false}) async {
    if (updateCheckBusy) {
      return UpdateCheckResult(outcome: updateCheckOutcome, release: latestGithubRelease, message: updateStatusMessage);
    }
    updateCheckBusy = true;
    updateStatusMessage = manual ? 'Checking Koinly releases now...' : 'Checking Koinly releases...';
    notifyListeners();
    final result = await updateService.check(installedVersion: appVersion);
    updateCheckBusy = false;
    updateCheckOutcome = result.outcome;
    latestGithubRelease = result.release;
    updateLastCheckedAt = DateTime.now();
    updateStatusMessage = result.message.isEmpty ? _friendlyUpdateOutcome(result.outcome) : result.message;
    if (result.hasUpdate && Platform.isAndroid) {
      final assets = availableAndroidUpdateAssets;
      if (assets.containsKey(UpdateAssetKind.arm64)) {
        selectedAndroidUpdateKind = UpdateAssetKind.arm64;
      } else if (assets.isNotEmpty) {
        selectedAndroidUpdateKind = assets.keys.first;
      }
      if (pendingAndroidUpdateVersion.isNotEmpty && pendingAndroidUpdateVersion != result.release!.displayVersion) {
        await _clearPendingAndroidUpdate(deleteFile: true);
        await UpdateDownloadStore.cleanupStaleAndroidUpdates(keepVersion: result.release!.displayVersion);
      }
    } else if (Platform.isAndroid && _isPendingAndroidUpdateAlreadyInstalled()) {
      await _clearPendingAndroidUpdate(deleteFile: true);
    }
    if (result.hasUpdate && Platform.isWindows) {
      if (pendingWindowsUpdateVersion.isNotEmpty && pendingWindowsUpdateVersion != result.release!.displayVersion) {
        await _clearPendingWindowsUpdate(deleteFile: true);
      }
      await UpdateDownloadStore.cleanupStaleWindowsUpdates(keepVersion: result.release!.displayVersion);
    } else if (Platform.isWindows && _isPendingWindowsUpdateAlreadyInstalled()) {
      await _clearPendingWindowsUpdate(deleteFile: true);
    }
    notifyListeners();
    return result;
  }

  String _friendlyUpdateOutcome(UpdateCheckOutcome outcome) {
    switch (outcome) {
      case UpdateCheckOutcome.updateAvailable:
        return 'A new update is available.';
      case UpdateCheckOutcome.upToDate:
        return 'You are up to date.';
      case UpdateCheckOutcome.noReleaseAvailable:
        return 'No stable release is available yet.';
      case UpdateCheckOutcome.networkError:
        return 'Could not connect to GitHub. Check your internet and try again.';
      case UpdateCheckOutcome.rateLimited:
        return 'GitHub API rate limit reached. Please try again later.';
      case UpdateCheckOutcome.malformedData:
        return 'GitHub returned release data that Koinly could not read.';
      case UpdateCheckOutcome.httpError:
        return 'GitHub update check failed.';
    }
  }

  Future<void> downloadSelectedAndroidUpdate() async {
    if (!Platform.isAndroid) {
      updateStatusMessage = 'In-app APK installation is available on Android only.';
      notifyListeners();
      return;
    }
    final release = latestGithubRelease;
    final asset = selectedAndroidUpdateAsset;
    if (release == null || asset == null) {
      updateStatusMessage = 'This release does not include a matching Android APK.';
      notifyListeners();
      return;
    }
    if (!ReleaseAssetMatcher.isTrustedReleaseAssetUrl(asset.browserDownloadUrl)) {
      updateStatusMessage = 'Update asset is not from the configured GitHub release repository.';
      notifyListeners();
      return;
    }

    await UpdateDownloadStore.cleanupStaleAndroidUpdates(keepVersion: release.displayVersion);
    await UpdateDownloadStore.cleanupPartialFiles();
    final apkFile = await UpdateDownloadStore.androidApkFile(release: release, kind: selectedAndroidUpdateKind, asset: asset);
    final partialFile = File('${apkFile.path}.part');
    if (await apkFile.exists()) {
      await _savePendingAndroidUpdate(path: apkFile.path, version: release.displayVersion, kind: selectedAndroidUpdateKind);
      await installPendingAndroidUpdate();
      return;
    }

    _updateDownloadClient?.close();
    _updateDownloadClient = http.Client();
    _updateDownloadCancelled = false;
    updateDownloadBusy = true;
    final startedAt = DateTime.now();
    updateDownloadProgress = DownloadProgressSnapshot(
      receivedBytes: 0,
      totalBytes: asset.sizeBytes,
      startedAt: startedAt,
      now: startedAt,
    );
    updateStatusMessage = 'Downloading ${selectedAndroidUpdateKind.label} update...';
    notifyListeners();

    IOSink? sink;
    try {
      final request = http.Request('GET', Uri.parse(asset.browserDownloadUrl))
        ..headers.addAll(const {'Accept': 'application/octet-stream', 'User-Agent': 'Koinly-Updater'});
      final response = await _updateDownloadClient!.send(request).timeout(const Duration(seconds: 20));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException('HTTP ${response.statusCode}');
      }
      final total = response.contentLength ?? asset.sizeBytes;
      sink = partialFile.openWrite();
      var received = 0;
      var lastNotify = DateTime.now();
      await for (final chunk in response.stream) {
        received += chunk.length;
        sink.add(chunk);
        final now = DateTime.now();
        if (now.difference(lastNotify).inMilliseconds >= 140 || received == total) {
          updateDownloadProgress = DownloadProgressSnapshot(
            receivedBytes: received,
            totalBytes: total,
            startedAt: startedAt,
            now: now,
          );
          lastNotify = now;
          notifyListeners();
        }
      }
      await sink.close();
      sink = null;
      if (await apkFile.exists()) await apkFile.delete();
      await partialFile.rename(apkFile.path);
      updateDownloadProgress = DownloadProgressSnapshot(
        receivedBytes: total <= 0 ? received : total,
        totalBytes: total <= 0 ? received : total,
        startedAt: startedAt,
        now: DateTime.now(),
        status: 'Complete',
      );
      updateStatusMessage = 'Download complete. Opening Android installer...';
      updateDownloadBusy = false;
      await _savePendingAndroidUpdate(path: apkFile.path, version: release.displayVersion, kind: selectedAndroidUpdateKind);
      notifyListeners();
      await installPendingAndroidUpdate();
    } catch (_) {
      try {
        await sink?.close();
      } catch (_) {}
      updateDownloadBusy = false;
      updateDownloadProgress = null;
      if (!_updateDownloadCancelled) {
        updateStatusMessage = 'Download failed or was interrupted. Please try again.';
      }
      if (await partialFile.exists()) {
        try {
          await partialFile.delete();
        } catch (_) {}
      }
      notifyListeners();
    }
  }

  Future<void> cancelUpdateDownload() async {
    _updateDownloadCancelled = true;
    _updateDownloadClient?.close();
    _updateDownloadClient = null;
    updateDownloadBusy = false;
    updateDownloadProgress = null;
    updateStatusMessage = 'Download cancelled.';
    await UpdateDownloadStore.cleanupPartialFiles();
    notifyListeners();
  }

  Future<void> installPendingAndroidUpdate() async {
    if (!Platform.isAndroid) return;
    if (_isPendingAndroidUpdateAlreadyInstalled()) {
      await _clearPendingAndroidUpdate(deleteFile: true);
      updateStatusMessage = 'Koinly is already updated.';
      notifyListeners();
      return;
    }
    if (pendingAndroidUpdatePath.isEmpty || !await File(pendingAndroidUpdatePath).exists()) {
      await _clearPendingAndroidUpdate();
      updateStatusMessage = 'Downloaded update was not found. Please download it again.';
      notifyListeners();
      return;
    }
    try {
      final allowed = await AndroidUpdateInstaller.canInstallPackages();
      if (!allowed) {
        updateStatusMessage = 'Allow Koinly to install unknown apps, then return here to continue.';
        notifyListeners();
        await AndroidUpdateInstaller.openInstallPermissionSettings();
        return;
      }
      final opened = await AndroidUpdateInstaller.installApk(pendingAndroidUpdatePath);
      updateStatusMessage = opened ? 'Android installer opened. Complete installation to update Koinly.' : 'Could not open Android installer.';
      notifyListeners();
    } catch (_) {
      updateStatusMessage = 'Could not open Android installer. Please try again.';
      notifyListeners();
    }
  }

  Future<void> resumePendingAndroidInstallIfAllowed() async {
    if (!Platform.isAndroid || pendingAndroidUpdatePath.isEmpty || updateDownloadBusy) return;
    if (_isPendingAndroidUpdateAlreadyInstalled()) {
      await _clearPendingAndroidUpdate(deleteFile: true);
      updateStatusMessage = 'Koinly is already updated.';
      notifyListeners();
      return;
    }
    try {
      if (await AndroidUpdateInstaller.canInstallPackages()) {
        await installPendingAndroidUpdate();
      }
    } catch (_) {
      // Keep the pending APK so the user can retry from Settings > Updates.
    }
  }

  Future<void> downloadWindowsUpdate({bool force = false}) async {
    if (!Platform.isWindows) {
      updateStatusMessage = 'In-app Windows installer download is available on Windows only.';
      notifyListeners();
      return;
    }
    final release = latestGithubRelease;
    final asset = windowsUpdateInstallerAsset;
    if (release == null || asset == null) {
      updateStatusMessage = 'This release does not include a Windows installer.';
      notifyListeners();
      return;
    }
    if (!ReleaseAssetMatcher.isTrustedReleaseAssetUrl(asset.browserDownloadUrl)) {
      updateStatusMessage = 'Update asset is not from the configured GitHub release repository.';
      notifyListeners();
      return;
    }

    await UpdateDownloadStore.cleanupStaleWindowsUpdates(keepVersion: release.displayVersion);
    await UpdateDownloadStore.cleanupPartialFiles();
    final installerFile = await UpdateDownloadStore.windowsInstallerFile(release: release, asset: asset);
    final partialFile = File('${installerFile.path}.part');
    if (await installerFile.exists()) {
      if (force) {
        try {
          await installerFile.delete();
        } catch (_) {
          updateStatusMessage = 'Could not replace the previously downloaded installer. Please try again.';
          notifyListeners();
          return;
        }
        await _clearPendingWindowsUpdate();
      } else {
        await _savePendingWindowsUpdate(path: installerFile.path, version: release.displayVersion);
        await installPendingWindowsUpdate();
        return;
      }
    }

    _updateDownloadClient?.close();
    _updateDownloadClient = http.Client();
    _updateDownloadCancelled = false;
    updateDownloadBusy = true;
    final startedAt = DateTime.now();
    updateDownloadProgress = DownloadProgressSnapshot(
      receivedBytes: 0,
      totalBytes: asset.sizeBytes,
      startedAt: startedAt,
      now: startedAt,
    );
    updateStatusMessage = 'Downloading Windows installer...';
    notifyListeners();

    IOSink? sink;
    try {
      final request = http.Request('GET', Uri.parse(asset.browserDownloadUrl))
        ..headers.addAll(const {'Accept': 'application/octet-stream', 'User-Agent': 'Koinly-Updater'});
      final response = await _updateDownloadClient!.send(request).timeout(const Duration(seconds: 20));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException('HTTP ${response.statusCode}');
      }
      final total = response.contentLength ?? asset.sizeBytes;
      sink = partialFile.openWrite();
      var received = 0;
      var lastNotify = DateTime.now();
      await for (final chunk in response.stream) {
        received += chunk.length;
        sink.add(chunk);
        final now = DateTime.now();
        if (now.difference(lastNotify).inMilliseconds >= 140 || (total > 0 && received >= total)) {
          updateDownloadProgress = DownloadProgressSnapshot(
            receivedBytes: received,
            totalBytes: total,
            startedAt: startedAt,
            now: now,
          );
          lastNotify = now;
          notifyListeners();
        }
      }
      await sink.close();
      sink = null;
      if (await installerFile.exists()) await installerFile.delete();
      await partialFile.rename(installerFile.path);
      final completedTotal = total <= 0 ? received : total;
      updateDownloadProgress = DownloadProgressSnapshot(
        receivedBytes: completedTotal,
        totalBytes: completedTotal,
        startedAt: startedAt,
        now: DateTime.now(),
        status: 'Complete',
      );
      updateDownloadBusy = false;
      updateStatusMessage = 'Download complete. Opening Windows installer...';
      await _savePendingWindowsUpdate(path: installerFile.path, version: release.displayVersion);
      notifyListeners();
      await installPendingWindowsUpdate();
    } catch (_) {
      try {
        await sink?.close();
      } catch (_) {}
      updateDownloadBusy = false;
      updateDownloadProgress = null;
      if (!_updateDownloadCancelled) {
        updateStatusMessage = 'Windows update download failed or was interrupted. Please try again.';
      }
      if (await partialFile.exists()) {
        try {
          await partialFile.delete();
        } catch (_) {}
      }
      notifyListeners();
    }
  }

  Future<void> installPendingWindowsUpdate() async {
    if (!Platform.isWindows) return;
    if (_isPendingWindowsUpdateAlreadyInstalled()) {
      await _clearPendingWindowsUpdate(deleteFile: true);
      updateStatusMessage = 'Koinly is already updated.';
      notifyListeners();
      return;
    }
    if (pendingWindowsUpdatePath.isEmpty || !await File(pendingWindowsUpdatePath).exists()) {
      await _clearPendingWindowsUpdate();
      updateStatusMessage = 'Downloaded Windows installer was not found. Please download it again.';
      notifyListeners();
      return;
    }
    final opened = await WindowsUpdateInstaller.install(pendingWindowsUpdatePath);
    updateStatusMessage = opened
        ? 'Windows installer opened. Complete installation to update Koinly.'
        : 'Could not open the downloaded Windows installer. Please try again.';
    notifyListeners();
  }

  Future<void> _savePendingWindowsUpdate({required String path, required String version}) async {
    pendingWindowsUpdatePath = path;
    pendingWindowsUpdateVersion = version;
    await prefs.setString('pendingWindowsUpdatePath', path);
    await prefs.setString('pendingWindowsUpdateVersion', version);
  }

  bool _isPendingWindowsUpdateAlreadyInstalled() {
    if (pendingWindowsUpdateVersion.trim().isEmpty) return false;
    final installed = SemanticVersion.tryParse(appVersion);
    final pending = SemanticVersion.tryParse(pendingWindowsUpdateVersion);
    if (installed == null || pending == null) return false;
    return pending.compareTo(installed) <= 0;
  }

  Future<void> _clearPendingWindowsUpdate({bool deleteFile = false}) async {
    if (deleteFile && pendingWindowsUpdatePath.isNotEmpty) {
      final file = File(pendingWindowsUpdatePath);
      if (await file.exists()) {
        try {
          await file.delete();
        } catch (_) {}
      }
    }
    pendingWindowsUpdatePath = '';
    pendingWindowsUpdateVersion = '';
    final sp = await prefs.prefs;
    await sp.remove('pendingWindowsUpdatePath');
    await sp.remove('pendingWindowsUpdateVersion');
  }

  Future<void> _savePendingAndroidUpdate({required String path, required String version, required UpdateAssetKind kind}) async {
    pendingAndroidUpdatePath = path;
    pendingAndroidUpdateVersion = version;
    pendingAndroidUpdateKind = kind;
    await prefs.setString('pendingAndroidUpdatePath', path);
    await prefs.setString('pendingAndroidUpdateVersion', version);
    await prefs.setString('pendingAndroidUpdateKind', enumName(kind));
  }

  bool _isPendingAndroidUpdateAlreadyInstalled() {
    if (pendingAndroidUpdateVersion.trim().isEmpty) return false;
    final installed = SemanticVersion.tryParse(appVersion);
    final pending = SemanticVersion.tryParse(pendingAndroidUpdateVersion);
    if (installed == null || pending == null) return false;
    return pending.compareTo(installed) <= 0;
  }

  Future<void> _clearPendingAndroidUpdate({bool deleteFile = false}) async {
    if (deleteFile && pendingAndroidUpdatePath.isNotEmpty) {
      final file = File(pendingAndroidUpdatePath);
      if (await file.exists()) {
        try {
          await file.delete();
        } catch (_) {}
      }
    }
    pendingAndroidUpdatePath = '';
    pendingAndroidUpdateVersion = '';
    pendingAndroidUpdateKind = null;
    final sp = await prefs.prefs;
    await sp.remove('pendingAndroidUpdatePath');
    await sp.remove('pendingAndroidUpdateVersion');
    await sp.remove('pendingAndroidUpdateKind');
  }

  Future<void> configureCloudSync({required bool enabled, required String apiBaseUrl, required String syncId, required String pin}) async {
    // Automatic sync is always on once an online sync method is configured.
    cloudSyncEnabled = true;
    cloudSyncApiBaseUrl = CloudSyncService.resolveApiBaseUrl(apiBaseUrl);
    cloudSyncId = CloudSyncService.normalizeSyncId(syncId);
    cloudSyncPin = pin.trim();
    cloudSyncError = null;
    cloudSyncErrorCode = null;
    await prefs.setBool('cloudSyncEnabled', cloudSyncEnabled);
    await prefs.setString('cloudSyncApiBaseUrl', cloudSyncApiBaseUrl);
    await prefs.setString('cloudSyncId', cloudSyncId);
    await secureCredentials.writeCloudSyncPin(cloudSyncPin);
    await (await prefs.prefs).remove('cloudSyncPin');
    notifyListeners();
  }

  Future<void> ensureCloudSyncCredentials() async {
    var changed = false;
    if (cloudSyncId.trim().isEmpty) {
      final shortId = _uuid.v4().split('-').first.toLowerCase();
      cloudSyncId = CloudSyncService.normalizeSyncId('koinly-$shortId');
      changed = true;
    }
    if (cloudSyncPin.trim().isEmpty) {
      cloudSyncPin = _uuid.v4().replaceAll('-', '').substring(0, 8);
      changed = true;
    }
    if (!changed) return;
    await prefs.setString('cloudSyncId', cloudSyncId);
    await secureCredentials.writeCloudSyncPin(cloudSyncPin);
    await (await prefs.prefs).remove('cloudSyncPin');
    notifyListeners();
  }

  Future<void> ensureMongoDbSyncCredentials() async {
    var changed = false;
    if (syncMongoSyncId.trim().isEmpty) {
      final shortId = _uuid.v4().split('-').first.toLowerCase();
      syncMongoSyncId = CloudSyncService.normalizeSyncId('mongo-$shortId');
      changed = true;
    }
    if (syncMongoSyncPin.trim().isEmpty) {
      syncMongoSyncPin = _uuid.v4().replaceAll('-', '').substring(0, 8);
      changed = true;
    }
    if (!changed) return;
    notifyListeners();
  }

  Future<void> configureSyncDatabase({
    required SyncDatabaseProvider provider,
    required String apiBaseUrl,
    required String mongoDbUrl,
    required String mongoDatabaseName,
    required String mongoCollectionName,
    required String tursoDatabaseUrl,
    required String tursoAuthToken,
  }) async {
    provider = userSyncDatabaseProviders.contains(provider) ? provider : SyncDatabaseProvider.mongoDb;
    syncDatabaseProvider = provider;
    cloudSyncApiBaseUrl = CloudSyncService.resolveApiBaseUrl(apiBaseUrl);
    syncMongoDbUrl = mongoDbUrl.trim();
    syncMongoDatabaseName = MongoDbSyncService.normalizeDatabaseName(mongoDatabaseName);
    syncMongoCollectionName = MongoDbSyncService.normalizeCollectionName(mongoCollectionName);
    syncTursoDatabaseUrl = tursoDatabaseUrl.trim();
    syncTursoAuthToken = tursoAuthToken.trim();
    cloudSyncError = null;
    cloudSyncErrorCode = null;
    if (provider == SyncDatabaseProvider.local) {
      cloudSyncEnabled = false;
      cloudSyncLastAt = null;
      await prefs.setBool('cloudSyncEnabled', false);
    } else {
      cloudSyncEnabled = true;
      await prefs.setBool('cloudSyncEnabled', true);
    }
    await prefs.setEnum('syncDatabaseProvider', provider);
    await prefs.setString('cloudSyncApiBaseUrl', cloudSyncApiBaseUrl);
    await prefs.setString('syncMongoDatabaseName', syncMongoDatabaseName);
    await prefs.setString('syncMongoCollectionName', syncMongoCollectionName);
    await prefs.setString('syncTursoDatabaseUrl', syncTursoDatabaseUrl);
    await secureCredentials.writeMongoDbUrl(syncMongoDbUrl);
    await secureCredentials.writeTursoAuthToken(syncTursoAuthToken);
    if (cloudSyncPending) _schedulePendingSyncRetry(immediate: true);
    notifyListeners();
  }

  Future<void> testSyncDatabaseConnection({
    SyncDatabaseProvider? provider,
    String? apiBaseUrl,
    String? mongoDbUrl,
    String? mongoDatabaseName,
    String? mongoCollectionName,
  }) async {
    final resolvedProvider = provider ?? syncDatabaseProvider;
    switch (resolvedProvider) {
      case SyncDatabaseProvider.local:
        return;
      case SyncDatabaseProvider.turso:
      case SyncDatabaseProvider.cloudflareD1:
      case SyncDatabaseProvider.supabase:
      case SyncDatabaseProvider.neonPostgres:
      case SyncDatabaseProvider.firebaseFirestore:
        await CloudSyncService.testBackend(apiBaseUrl ?? cloudSyncApiBaseUrl);
        return;
      case SyncDatabaseProvider.mongoDb:
        await MongoDbSyncService.testConnection(
          connectionString: mongoDbUrl ?? syncMongoDbUrl,
          databaseName: mongoDatabaseName ?? syncMongoDatabaseName,
          collectionName: mongoCollectionName ?? syncMongoCollectionName,
        );
        return;
    }
  }

  Future<Map<String, dynamic>> _mergeLegacyCloudPayloads(
    Map<String, dynamic> currentPayload,
    Map<String, dynamic> incomingPayload,
  ) async {
    final currentDatabase = (currentPayload['database'] as Map? ?? const {}).cast<String, dynamic>();
    final incomingDatabase = (incomingPayload['database'] as Map? ?? const {}).cast<String, dynamic>();
    final mergedDatabase = mergeFinanceDatabasePayloads(currentDatabase, incomingDatabase);
    final currentPreferences = (currentPayload['preferences'] as Map? ?? const {}).cast<String, dynamic>();
    final incomingPreferences = (incomingPayload['preferences'] as Map? ?? const {}).cast<String, dynamic>();
    return {
      'version': CloudSyncService.payloadVersion,
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'database': mergedDatabase.database,
      'preferences': mergeFinancePreferences(currentPreferences, incomingPreferences, mergedDatabase.categoryPlan),
    };
  }

  Future<void> _adoptMergedLegacyCloudPayload(Map<String, dynamic> payload) async {
    final databasePayload = (payload['database'] as Map? ?? const {}).cast<String, dynamic>();
    final preferencesPayload = (payload['preferences'] as Map? ?? const {}).cast<String, dynamic>();
    final plan = await database.importAll(databasePayload);
    await importPreferences(remapCategoryPreferences(preferencesPayload, plan));
    await reload(queueSync: false);
  }

  Future<void> syncMainOnlineToCloud({bool force = false}) async {
    if (cloudSyncBusy) return;
    if (cloudSyncId.trim().isEmpty || cloudSyncPin.trim().isEmpty) {
      await ensureCloudSyncCredentials();
    }
    cloudSyncBusy = true;
    cloudSyncError = null;
    cloudSyncErrorCode = null;
    notifyListeners();
    try {
      final localPayload = await exportCloudPayload();
      Map<String, dynamic>? cloudPayload;
      try {
        cloudPayload = await CloudSyncService.download(
          apiBaseUrl: cloudSyncApiBaseUrl,
          syncId: cloudSyncId,
          pin: cloudSyncPin,
        );
      } on CloudSyncException catch (error) {
        // A brand-new legacy Sync ID has nothing to merge yet. Any other
        // failure (wrong PIN, approval, network/backend issue) must still stop
        // the upload instead of risking an accidental overwrite.
        if (!error.message.toLowerCase().contains('no cloud data found')) rethrow;
      }

      var payload = localPayload;
      if (cloudPayload != null) {
        await requireSafetyBackup('Before legacy online cloud merge');
        // Incoming is local here, so local scalar preferences win while all
        // finance entities from both snapshots are retained and categories are
        // semantically deduplicated.
        payload = await _mergeLegacyCloudPayloads(cloudPayload, localPayload);
        await _adoptMergedLegacyCloudPayload(payload);
      }
      await CloudSyncService.upload(
        apiBaseUrl: cloudSyncApiBaseUrl,
        syncId: cloudSyncId,
        pin: cloudSyncPin,
        payload: payload,
      );
      cloudSyncLastAt = DateTime.now();
      await prefs.setString('cloudSyncLastAt', cloudSyncLastAt!.toIso8601String());
    } catch (error) {
      cloudSyncError = _cleanSyncError(error);
      cloudSyncErrorCode = error is CloudSyncException ? error.code : null;
    } finally {
      cloudSyncBusy = false;
      notifyListeners();
    }
  }

  Future<void> syncMainOnlineFromCloud() async {
    if (cloudSyncBusy) return;
    if (cloudSyncId.trim().isEmpty || cloudSyncPin.trim().isEmpty) {
      cloudSyncError = 'Enter a Sync ID and PIN on the main Online data sync page, or upload first to create them.';
      notifyListeners();
      return;
    }
    cloudSyncBusy = true;
    cloudSyncError = null;
    cloudSyncErrorCode = null;
    notifyListeners();
    try {
      final cloudPayload = await CloudSyncService.download(
        apiBaseUrl: cloudSyncApiBaseUrl,
        syncId: cloudSyncId,
        pin: cloudSyncPin,
      );
      final localPayload = await exportCloudPayload();
      await requireSafetyBackup('Before legacy online cloud merge');
      // Incoming is cloud here, so cloud scalar preferences win, while
      // local-only finance rows remain present in the merged device copy.
      final mergedPayload = await _mergeLegacyCloudPayloads(localPayload, cloudPayload);
      await _adoptMergedLegacyCloudPayload(mergedPayload);
      // Snapshot sync has no per-entity outbox, so write the merged union back
      // immediately to make both sides converge without deleting either side.
      await CloudSyncService.upload(
        apiBaseUrl: cloudSyncApiBaseUrl,
        syncId: cloudSyncId,
        pin: cloudSyncPin,
        payload: mergedPayload,
      );
      cloudSyncEnabled = true;
      await prefs.setBool('cloudSyncEnabled', true);
      await prefs.setString('cloudSyncApiBaseUrl', cloudSyncApiBaseUrl);
      await prefs.setString('cloudSyncId', cloudSyncId);
      await secureCredentials.writeCloudSyncPin(cloudSyncPin);
      await (await prefs.prefs).remove('cloudSyncPin');
      cloudSyncLastAt = DateTime.now();
      await prefs.setString('cloudSyncLastAt', cloudSyncLastAt!.toIso8601String());
    } catch (error) {
      cloudSyncError = _cleanSyncError(error);
      cloudSyncErrorCode = error is CloudSyncException ? error.code : null;
    } finally {
      cloudSyncBusy = false;
      notifyListeners();
    }
  }

  Future<void> syncToCloud({bool force = false, bool silent = false}) async {
    if (authoritativeCloudUploadPending) {
      // v1.0.1067 migrates the old destructive "authoritative restore" flag
      // into normal merge sync. Never call the server replace-all endpoint.
      await _prepareRestoredDataForMergeSync();
    }
    if (force) {
      // A manual "Upload local changes" / Telegram-backup preparation must
      // reconcile the complete local snapshot, not only rows that happened to
      // enter the outbox after this account was linked. This is especially
      // important when a user signs in to a new self-hosted Worker while the
      // device already contains finance data.
      await _repairDuplicateCategories(queueSyncChanges: false);
      await database.enqueueAllForAdoption(await exportPreferences());
      await _setCloudSyncPending(true);
    }
    await performMultiDeviceSync(silent: silent, pullFullCloudCopy: force);
    if (force) {
      // Conflict rebasing can create a second generation of outbox rows. A
      // forced reconciliation is used before manual cloud upload and Telegram
      // backup, so finish those rebased operations now instead of relying on a
      // later background retry.
      var settlePass = 0;
      while (settlePass < 4 && await database.pendingSyncOperationCount() > 0) {
        settlePass += 1;
        await performMultiDeviceSync(silent: silent, pushLocalChanges: true, pullFullCloudCopy: true);
      }
      if (await database.pendingSyncOperationCount() > 0 && !silent) {
        cloudSyncError ??= 'Some local data is still waiting to sync. Try Upload local changes again before creating a Telegram backup.';
        syncStatus = 'Sync pending';
        notifyListeners();
      }
    }
  }

  Future<void> syncFromCloud() async {
    // A cloud restore is now a two-way merge: local changes are preserved and
    // uploaded, while the complete cloud history is folded into this device.
    await performMultiDeviceSync(pushLocalChanges: true, pullFullCloudCopy: true);
  }

  Future<T> _withSelfHostedSyncToken<T>(Future<T> Function(KoinlySyncApi api, String accessToken) action) async {
    if (selfHostedSyncApiBaseUrl.isEmpty) {
      throw StateError('Validate your self-hosted Sync Worker first.');
    }
    if (!cloudSyncEnabled || syncAccessToken.isEmpty || syncRefreshToken.isEmpty) {
      throw StateError('Sign in to the self-hosted Sync Worker first.');
    }
    final api = KoinlySyncApi(baseUrl: cloudSyncApiBaseUrl);
    try {
      return await action(api, syncAccessToken);
    } catch (error) {
      final text = _cleanSyncError(error).toLowerCase();
      if (!text.contains('expired') && !text.contains('access token')) rethrow;
      await _refreshSyncSession();
      return action(api, syncAccessToken);
    }
  }

  Future<TelegramBackupSettings> loadSelfHostedTelegramBackupSettings() {
    return _withSelfHostedSyncToken((api, accessToken) => api.telegramBackupSettings(accessToken: accessToken));
  }

  Future<TelegramBackupSettings> saveSelfHostedTelegramBackupSettings({
    required bool enabled,
    required String botToken,
    required String chatId,
    required TelegramBackupFrequency frequency,
    required int hour,
    required int minute,
    required int weekday,
    required int monthDay,
  }) {
    return _withSelfHostedSyncToken((api, accessToken) => api.saveTelegramBackupSettings(
          accessToken: accessToken,
          enabled: enabled,
          botToken: botToken,
          chatId: chatId,
          frequency: frequency,
          hour: hour,
          minute: minute,
          weekday: weekday,
          monthDay: monthDay,
          timezoneOffsetMinutes: DateTime.now().timeZoneOffset.inMinutes,
        ));
  }

  Future<void> testSelfHostedTelegramBackup({String botToken = '', String chatId = ''}) {
    return _withSelfHostedSyncToken((api, accessToken) => api.testTelegramBackup(
          accessToken: accessToken,
          botToken: botToken,
          chatId: chatId,
        ));
  }

  Future<Map<String, dynamic>> sendSelfHostedTelegramBackupNow() async {
    // Make the cloud snapshot complete before asking the Worker to package it.
    // Without this reconciliation, data that existed before the device signed
    // in to this self-hosted account could be absent from sync_entities even
    // though the UI correctly showed the local database as synced.
    await syncToCloud(force: true, silent: false);
    if (cloudSyncError != null) {
      throw StateError('Could not sync local data before creating the Telegram backup: $cloudSyncError');
    }
    return _withSelfHostedSyncToken((api, accessToken) => api.sendTelegramBackupNow(accessToken: accessToken));
  }

  Future<void> configureSelfHostedSyncEndpoint(String apiBaseUrl) async {
    final nextApiBaseUrl = CloudSyncService.validateApiBaseUrl(apiBaseUrl);
    await KoinlySyncApi(baseUrl: nextApiBaseUrl).validateBackend();
    final endpointChanged = CloudSyncService.normalizeApiBaseUrl(cloudSyncApiBaseUrl) != nextApiBaseUrl;
    if (endpointChanged && cloudSyncEnabled) {
      await logoutSyncAccount();
    }
    selfHostedSyncApiBaseUrl = nextApiBaseUrl;
    cloudSyncApiBaseUrl = nextApiBaseUrl;
    cloudSyncError = null;
    cloudSyncErrorCode = null;
    await prefs.setString('selfHostedSyncApiBaseUrl', selfHostedSyncApiBaseUrl);
    await prefs.setString('cloudSyncApiBaseUrl', cloudSyncApiBaseUrl);
    notifyListeners();
  }

  Future<String?> registerSyncAccount({
    required String username,
    required String password,
    bool deferInitialDataSync = false,
  }) async {
    return _authenticateSyncAccount(
      register: true,
      username: username,
      password: password,
      deferInitialDataSync: deferInitialDataSync,
    );
  }

  Future<void> loginSyncAccount({required String username, required String password, bool preferCloudData = true}) async {
    await _authenticateSyncAccount(register: false, username: username, password: password, preferCloudData: preferCloudData);
  }

  Future<String?> _authenticateSyncAccount({
    required bool register,
    required String username,
    required String password,
    bool preferCloudData = true,
    bool deferInitialDataSync = false,
  }) async {
    syncAuthBusy = true;
    cloudSyncError = null;
    syncStatus = register ? 'Creating account...' : 'Signing in...';
    notifyListeners();
    try {
      if (cloudSyncApiBaseUrl.isEmpty) {
        throw StateError('Validate your self-hosted Sync Worker first.');
      }
      final api = KoinlySyncApi(baseUrl: cloudSyncApiBaseUrl);
      final session = register
          ? await api.register(
              username: username,
              password: password,
              deviceId: syncDeviceId,
              deviceName: _deviceName(),
              platform: _platformName(),
            )
          : await api.login(username: username, password: password, deviceId: syncDeviceId, deviceName: _deviceName(), platform: _platformName());
      await _saveSyncSession(session);
      await database.writeSyncState('serverCursor', '0');
      if (!register || !deferInitialDataSync) {
        newSyncAccountAwaitingSetupChoice = false;
        await prefs.setBool('newSyncAccountAwaitingSetupChoice', false);
      }
      if (authoritativeCloudUploadPending) {
        await _prepareRestoredDataForMergeSync();
      }
      if (register && deferInitialDataSync) {
        newSyncAccountAwaitingSetupChoice = true;
        await prefs.setBool('newSyncAccountAwaitingSetupChoice', true);
        await _setCloudSyncPending(false);
        syncStatus = 'Account created • Choose setup';
      } else if (register) {
        await _repairDuplicateCategories(queueSyncChanges: false);
        await database.enqueueAllForAdoption(await exportPreferences());
        await performMultiDeviceSync(silent: true);
      } else {
        await _mergeAfterExistingAccountAuth(preferCloudData: preferCloudData);
      }
      if (!(register && deferInitialDataSync)) {
        _startCloudAutoPull();
      }
      return session.recoveryKey;
    } catch (error) {
      cloudSyncError = _cleanSyncError(error);
      syncStatus = 'Sync error';
      return null;
    } finally {
      syncAuthBusy = false;
      notifyListeners();
    }
  }

  Future<void> recoverSyncAccount({
    required String username,
    required String recoveryKey,
    required String newPassword,
    bool preferCloudData = true,
  }) async {
    syncAuthBusy = true;
    cloudSyncError = null;
    syncStatus = 'Recovering account...';
    notifyListeners();
    try {
      if (cloudSyncApiBaseUrl.isEmpty) {
        throw StateError('Validate your self-hosted Sync Worker first.');
      }
      final session = await KoinlySyncApi(baseUrl: cloudSyncApiBaseUrl).recoverAccount(
        username: username,
        recoveryKey: recoveryKey,
        newPassword: newPassword,
        deviceId: syncDeviceId,
        deviceName: _deviceName(),
        platform: _platformName(),
      );
      await _saveSyncSession(session);
      await database.writeSyncState('serverCursor', '0');
      newSyncAccountAwaitingSetupChoice = false;
      await prefs.setBool('newSyncAccountAwaitingSetupChoice', false);
      if (authoritativeCloudUploadPending) {
        await _prepareRestoredDataForMergeSync();
      }
      await _mergeAfterExistingAccountAuth(preferCloudData: preferCloudData);
      _startCloudAutoPull();
    } catch (error) {
      cloudSyncError = _cleanSyncError(error);
      syncStatus = 'Sync error';
    } finally {
      syncAuthBusy = false;
      notifyListeners();
    }
  }

  Future<String?> rotateSyncRecoveryKey() async {
    if (!cloudSyncEnabled || syncAccessToken.isEmpty) return null;
    syncAuthBusy = true;
    cloudSyncError = null;
    notifyListeners();
    try {
      return await KoinlySyncApi(baseUrl: cloudSyncApiBaseUrl).rotateRecoveryKey(accessToken: syncAccessToken);
    } catch (error) {
      cloudSyncError = _cleanSyncError(error);
      return null;
    } finally {
      syncAuthBusy = false;
      notifyListeners();
    }
  }

  Future<void> _mergeAfterExistingAccountAuth({required bool preferCloudData}) async {
    // Existing-account authentication is a two-phase merge. Pull the complete
    // cloud state first so server versions are known, then adopt the merged
    // local snapshot back to cloud. Local-only records are preserved.
    await discardPreloadedStarterAccountsForImport();
    await performMultiDeviceSync(
      silent: !preferCloudData,
      pushLocalChanges: false,
      pullFullCloudCopy: true,
    );
    final removedCloudStarterPlaceholders = await discardPreloadedStarterAccountsForImport();
    if (cloudSyncError == null) {
      await syncToCloud(force: true, silent: true);
    }
    if (removedCloudStarterPlaceholders && cloudSyncError == null) {
      await performMultiDeviceSync(silent: true, pushLocalChanges: true, pullFullCloudCopy: true);
    }
  }

  Future<void> logoutSyncAccount() async {
    syncAuthBusy = true;
    notifyListeners();
    try {
      if (syncAccessToken.isNotEmpty && syncRefreshToken.isNotEmpty && cloudSyncApiBaseUrl.isNotEmpty) {
        await KoinlySyncApi(baseUrl: cloudSyncApiBaseUrl).logout(accessToken: syncAccessToken, refreshToken: syncRefreshToken);
      }
    } catch (_) {
      // Local logout should still clear this device even if the server is offline.
    }
    await secureCredentials.clearAccountTokens();
    syncAccessToken = '';
    syncRefreshToken = '';
    syncAccountUsername = '';
    cloudSyncEnabled = false;
    newSyncAccountAwaitingSetupChoice = false;
    syncStatus = 'Offline';
    await prefs.setString('syncAccountUsername', '');
    await prefs.setBool('cloudSyncEnabled', false);
    await prefs.setBool('newSyncAccountAwaitingSetupChoice', false);
    // Entity versions/cursors belong to one authenticated backend/account.
    // Never carry them into another self-hosted account; finance rows
    // stay local and will be merged/adopted again after the next login.
    await database.resetLocalSyncTracking();
    await database.writeSyncState('serverCursor', '0');
    await _setCloudSyncPending(false);
    _stopCloudAutoPull();
    syncAuthBusy = false;
    notifyListeners();
  }

  Future<void> _saveSyncSession(SyncAuthSession session) async {
    syncAccessToken = session.accessToken;
    syncRefreshToken = session.refreshToken;
    syncAccountUsername = session.username;
    syncDeviceId = session.deviceId.isNotEmpty ? session.deviceId : syncDeviceId;
    cloudSyncEnabled = syncAccessToken.isNotEmpty && syncRefreshToken.isNotEmpty;
    await secureCredentials.writeAccessToken(syncAccessToken);
    await secureCredentials.writeRefreshToken(syncRefreshToken);
    await prefs.setString('syncAccountUsername', syncAccountUsername);
    await prefs.setString('syncDeviceId', syncDeviceId);
    await prefs.setString('cloudSyncApiBaseUrl', cloudSyncApiBaseUrl);
    await prefs.setBool('cloudSyncEnabled', cloudSyncEnabled);
  }

  Future<void> _refreshSyncSession() async {
    if (syncRefreshToken.isEmpty) throw StateError('Sign in to sync first.');
    final session = await KoinlySyncApi(baseUrl: cloudSyncApiBaseUrl).refresh(refreshToken: syncRefreshToken, deviceId: syncDeviceId, username: syncAccountUsername);
    await _saveSyncSession(session);
    _restartCloudLiveConnection();
  }

  List<Map<String, dynamic>> _latestRemoteChangePerEntity(List<Map<String, dynamic>> changes) {
    if (changes.length < 2) return changes;
    final lastIndexByEntity = <String, int>{};
    for (var index = 0; index < changes.length; index += 1) {
      final change = changes[index];
      final entityType = change['entityType']?.toString() ?? '';
      final entityId = change['entityId']?.toString() ?? '';
      if (entityType.isEmpty || entityId.isEmpty) continue;
      lastIndexByEntity['$entityType\u0000$entityId'] = index;
    }
    final latest = <Map<String, dynamic>>[];
    for (var index = 0; index < changes.length; index += 1) {
      final change = changes[index];
      final entityType = change['entityType']?.toString() ?? '';
      final entityId = change['entityId']?.toString() ?? '';
      if (entityType.isEmpty || entityId.isEmpty) continue;
      if (lastIndexByEntity['$entityType\u0000$entityId'] == index) latest.add(change);
    }
    return latest;
  }

  Future<void> performMultiDeviceSync({bool silent = false, bool pushLocalChanges = true, bool pullFullCloudCopy = false}) async {
    if (!_hasConfiguredSyncTarget()) {
      if (!silent) {
        syncStatus = 'Sign in to sync first.';
        notifyListeners();
      }
      return;
    }
    if (_syncInProgress || cloudSyncBusy) {
      if (!silent) {
        syncStatus = 'Sync already running...';
        notifyListeners();
      }
      return;
    }
    _syncInProgress = true;
    cloudSyncBusy = !silent;
    if (!silent) {
      cloudSyncError = null;
      cloudSyncErrorCode = null;
      syncStatus = pushLocalChanges ? 'Checking local changes...' : 'Checking cloud data...';
      notifyListeners();
    }
    try {
      final api = KoinlySyncApi(baseUrl: cloudSyncApiBaseUrl);
      final conflictedLocalOperations = <String, Map<String, dynamic>>{};
      if (pushLocalChanges) {
        if (!silent) {
          syncStatus = 'Uploading local changes...';
          notifyListeners();
        }
        var uploadPass = 0;
        while (uploadPass < 100) {
          uploadPass += 1;
          final pending = await database.pendingSyncOperations(limit: 100);
          if (pending.isEmpty) break;
          final operations = pending.map(_operationFromOutboxRow).toList();
          final operationsById = {for (final operation in operations) operation['operationId']?.toString() ?? '': operation};
          final response = await api.push(accessToken: syncAccessToken, operations: operations);
          final accepted = (response['accepted'] as List? ?? const []).cast<Map>();
          final acceptedIds = <String>[];
          final versions = <String, int>{};
          for (final item in accepted) {
            final operationId = item['operationId']?.toString() ?? '';
            if (operationId.isEmpty) continue;
            acceptedIds.add(operationId);
            versions[operationId] = (item['version'] as num? ?? 0).toInt();
          }
          await database.markOutboxUploaded(acceptedIds, versions);

          final conflicts = (response['conflicts'] as List? ?? const []).cast<Map>();
          final conflictedIds = <String>[];
          for (final conflict in conflicts) {
            final operationId = conflict['operationId']?.toString() ?? '';
            if (operationId.isNotEmpty) {
              conflictedIds.add(operationId);
              final localOperation = operationsById[operationId];
              if (localOperation != null) {
                conflictedLocalOperations['${localOperation['entityType']}\u0000${localOperation['entityId']}'] = {
                  ...localOperation,
                  'serverVersion': (conflict['serverVersion'] as num? ?? 0).toInt(),
                };
              }
            }
            await database.saveSyncConflict(
              entityType: conflict['entityType']?.toString() ?? '',
              entityId: conflict['entityId']?.toString() ?? '',
              localOperationId: operationId.isEmpty ? null : operationId,
              serverVersion: (conflict['serverVersion'] as num? ?? 0).toInt(),
              details: jsonEncode(conflict),
            );
          }
          await database.markOutboxUploaded(conflictedIds, const {});

          // Avoid spinning forever on a malformed response that neither accepts
          // nor rejects the attempted operations.
          if (acceptedIds.isEmpty && conflictedIds.isEmpty) break;
        }
      }

      final fullPullForMerge = pullFullCloudCopy || conflictedLocalOperations.isNotEmpty;
      var cursor = fullPullForMerge ? 0 : (int.tryParse(await database.readSyncState('serverCursor', '0')) ?? 0);
      var hasMore = true;
      final remoteChanges = <Map<String, dynamic>>[];
      if (!silent) {
        syncStatus = fullPullForMerge ? 'Downloading cloud data to merge...' : 'Checking cloud changes...';
        notifyListeners();
      }
      while (hasMore) {
        final response = await api.pull(accessToken: syncAccessToken, cursor: cursor, limit: 100);
        final changes = (response['changes'] as List? ?? const []).whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
        remoteChanges.addAll(changes);
        cursor = (response['cursor'] as num? ?? cursor).toInt();
        hasMore = response['hasMore'] == true;
      }

      // Older app versions could emit a destructive __reset__ marker. For a
      // merge restore we never clear local data. We only discard obsolete cloud
      // history before the most recent reset and merge the cloud snapshot that
      // follows it.
      final lastResetIndex = remoteChanges.lastIndexWhere((change) => change['entityType'] == '__reset__');
      if (lastResetIndex >= 0) {
        remoteChanges.removeRange(0, lastResetIndex + 1);
      }
      final mergedRemoteChanges = _latestRemoteChangePerEntity(remoteChanges);

      var preservedNewerLocal = false;
      if (mergedRemoteChanges.isNotEmpty) {
        if (pullFullCloudCopy) {
          if (!silent) {
            syncStatus = 'Saving safety backup...';
            notifyListeners();
          }
          await requireSafetyBackup('Before cloud data merge');
        }
        if (!silent) {
          syncStatus = 'Merging cloud data...';
          notifyListeners();
        }
        preservedNewerLocal = await database.applyRemoteChanges(mergedRemoteChanges, mergeRemotePreferences);
      }
      // Rebase any upload conflicts even if the server returned no additional
      // change rows in this pull. This prevents a newer local edit from being
      // dropped simply because the conflicting server version was already at
      // the cursor boundary.
      final rebased = await _reapplyNewerConflictedLocalChanges(conflictedLocalOperations);
      final repair = await _repairDuplicateCategories(queueSyncChanges: true);
      final needsMergeCleanupUpload = preservedNewerLocal || rebased || repair.hasChanges;
      await database.writeSyncState('serverCursor', '$cursor');

      cloudSyncLastAt = DateTime.now();
      await prefs.setString('cloudSyncLastAt', cloudSyncLastAt!.toIso8601String());
      // Conflicts are automatically closed once their entity has no pending
      // local operation. This also clears stale conflict rows left behind by
      // older builds after a successful merge.
      await database.resolveSettledSyncConflicts(
        settledThrough: cloudSyncLastAt!.millisecondsSinceEpoch,
      );
      final pendingCount = await database.pendingSyncOperationCount();
      final stillPending = needsMergeCleanupUpload || pendingCount > 0;
      await _setCloudSyncPending(stillPending);
      if (stillPending) _schedulePendingSyncRetry(immediate: true);
      cloudSyncError = null;
      cloudSyncErrorCode = null;
      syncStatus = fullPullForMerge ? 'Cloud data merged' : 'Synced';
      if (mergedRemoteChanges.isNotEmpty || preservedNewerLocal || rebased || repair.hasChanges) {
        await reload(queueSync: false);
      }
    } catch (error) {
      final text = _cleanSyncError(error);
      if (text.toLowerCase().contains('expired') || text.toLowerCase().contains('access token')) {
        await _refreshSyncSession();
        _syncInProgress = false;
        cloudSyncBusy = false;
        await performMultiDeviceSync(silent: silent, pushLocalChanges: pushLocalChanges, pullFullCloudCopy: pullFullCloudCopy);
        return;
      }
      await _setCloudSyncPending(true);
      _schedulePendingSyncRetry();
      if (!silent) {
        cloudSyncError = text;
        cloudSyncErrorCode = error is CloudSyncException ? error.code : null;
      }
      syncStatus = 'Sync error';
    } finally {
      _syncInProgress = false;
      cloudSyncBusy = false;
      if (!silent) {
        notifyListeners();
      }
      if (_cloudRealtimePullPending && _hasConfiguredSyncTarget()) {
        _cloudRealtimePullPending = false;
        scheduleMicrotask(() => unawaited(syncCloudChangesIfIdle(force: true)));
      }
    }
  }

  Future<void> _prepareRestoredDataForMergeSync() async {
    if (!authoritativeCloudUploadPending) return;
    authoritativeCloudUploadPending = false;
    await prefs.setBool('authoritativeCloudUploadPending', false);
    await _repairDuplicateCategories(queueSyncChanges: false);
    await database.enqueueAllForAdoption(await exportPreferences());
    await _setCloudSyncPending(true);
  }

  Future<void> markRestoredDataForCloudUpload() async {
    // Keep the legacy preference only long enough to migrate older installs.
    // Restored data is now queued as ordinary upserts and merged with cloud
    // entities; the cloud database is never wiped by a local restore.
    authoritativeCloudUploadPending = true;
    await prefs.setBool('authoritativeCloudUploadPending', true);
    await _prepareRestoredDataForMergeSync();
    if (_hasConfiguredSyncTarget()) {
      await performMultiDeviceSync(pullFullCloudCopy: true);
    } else {
      syncStatus = 'Backup merged locally • Sign in to sync it';
      notifyListeners();
    }
  }

  Future<void> resolveNewSyncAccountWithLocalSetup() async {
    if (!newSyncAccountAwaitingSetupChoice) {
      if (_hasConfiguredSyncTarget()) _startCloudAutoPull();
      return;
    }

    newSyncAccountAwaitingSetupChoice = false;
    await prefs.setBool('newSyncAccountAwaitingSetupChoice', false);
    await _repairDuplicateCategories(queueSyncChanges: false);
    await database.enqueueAllForAdoption(await exportPreferences());
    await _setCloudSyncPending(true);
    syncStatus = 'New setup ready • Sync pending';
    notifyListeners();
    _startCloudAutoPull();
    _schedulePendingSyncRetry(immediate: true);
  }

  Future<void> resolveNewSyncAccountWithRestoredData() async {
    if (newSyncAccountAwaitingSetupChoice) {
      newSyncAccountAwaitingSetupChoice = false;
      await prefs.setBool('newSyncAccountAwaitingSetupChoice', false);
    }
    await markRestoredDataForCloudUpload();
    if (_hasConfiguredSyncTarget()) _startCloudAutoPull();
  }

  /// Backward-compatible entry point for installs that still have the old
  /// authoritative-upload flag. It deliberately performs a merge sync and
  /// never calls the server's destructive replace-all endpoint.
  Future<void> uploadAuthoritativeCloudData({bool silent = false}) async {
    await _prepareRestoredDataForMergeSync();
    if (!_hasConfiguredSyncTarget()) {
      if (!silent) {
        syncStatus = 'Backup merged locally • Sign in to sync it';
        notifyListeners();
      }
      return;
    }
    await performMultiDeviceSync(silent: silent, pullFullCloudCopy: true);
  }

  Future<bool> _reapplyNewerConflictedLocalChanges(Map<String, Map<String, dynamic>> conflicts) async {
    var queued = false;
    for (final candidate in conflicts.values) {
      final entityType = candidate['entityType']?.toString() ?? '';
      final entityId = candidate['entityId']?.toString() ?? '';
      final operation = candidate['operation']?.toString() ?? '';
      final serverVersion = (candidate['serverVersion'] as num? ?? 0).toInt();
      if (entityType.isEmpty || entityId.isEmpty || operation != 'upsert') continue;

      final rawPayload = candidate['payload'];
      if (rawPayload is! Map) continue;
      final payload = rawPayload.cast<String, Object?>();

      if (entityType == 'preferences') {
        final current = await exportPreferences();
        final merged = mergeFinancePreferences(current, payload.cast<String, dynamic>(), CategoryMergePlan.empty);
        await importPreferences(merged);
        await database.saveEntityVersion(entityType, entityId, serverVersion);
        await database.enqueuePreferences(await exportPreferences());
        queued = true;
        continue;
      }
      if (!KoinlyDatabase.syncTables.contains(entityType)) continue;

      final currentRow = await database.syncEntityRow(entityType, entityId);
      final localTimestamp = _mergeRowTimestamp(payload);
      final remoteTimestamp = currentRow == null ? -1 : _mergeRowTimestamp(currentRow);
      // serverVersion == 0 means the selected backend/account does not have
      // this entity at all. That is common after switching from Default to a
      // fresh Self-hosted Worker while local version metadata still referred to
      // the previous backend. Rebase to version 0 and upload the local row even
      // when its timestamp matches the row already present in the local DB.
      final shouldKeepLocal = serverVersion == 0 || currentRow == null || localTimestamp > remoteTimestamp;
      if (!shouldKeepLocal) continue;

      await database.upsertSyncEntityRow(entityType, payload);
      await database.saveEntityVersion(entityType, entityId, serverVersion);
      await database.enqueueSyncOperation(
        entityType: entityType,
        entityId: entityId,
        operation: 'upsert',
        payload: payload,
      );
      queued = true;
    }
    return queued;
  }

  int _mergeRowTimestamp(Map<String, Object?> row) {
    for (final key in const ['updated_on', 'created_on']) {
      final value = row[key];
      if (value is num) return value.toInt();
      if (value is String) {
        final number = int.tryParse(value);
        if (number != null) return number;
        final date = DateTime.tryParse(value);
        if (date != null) return date.millisecondsSinceEpoch;
      }
    }
    return 0;
  }

  Map<String, dynamic> _operationFromOutboxRow(Map<String, Object?> row) {
    final payloadRaw = row['payload_json']?.toString();
    return {
      'operationId': row['id']?.toString() ?? '',
      'entityType': row['entity_type']?.toString() ?? '',
      'entityId': row['entity_id']?.toString() ?? '',
      'operation': row['operation']?.toString() ?? 'upsert',
      'payload': payloadRaw == null || payloadRaw.isEmpty ? null : jsonDecode(payloadRaw),
      'baseVersion': (row['base_version'] as num? ?? 0).toInt(),
      'clientUpdatedAt': row['created_at'],
    };
  }

  bool _hasConfiguredSyncTarget() =>
      cloudSyncEnabled && cloudSyncApiBaseUrl.trim().isNotEmpty && syncAccessToken.trim().isNotEmpty && syncRefreshToken.trim().isNotEmpty;

  String _deviceName() {
    if (kIsWeb) return 'Koinly Web';
    try {
      return Platform.localHostname.isEmpty ? 'Koinly device' : Platform.localHostname;
    } catch (_) {
      return 'Koinly device';
    }
  }

  String _platformName() {
    if (kIsWeb) return 'web';
    if (Platform.isAndroid) return 'android';
    if (Platform.isWindows) return 'windows';
    if (Platform.isLinux) return 'linux';
    if (Platform.isMacOS) return 'macos';
    if (Platform.isIOS) return 'ios';
    return 'unknown';
  }

  Future<void> _setCloudSyncPending(bool value) async {
    cloudSyncPending = value;
    await prefs.setBool('cloudSyncPending', value);
  }

  void _schedulePendingSyncRetry({bool immediate = false}) {
    if (!_hasConfiguredSyncTarget()) return;
    if (immediate && cloudSyncPending && !cloudSyncBusy) {
      unawaited(syncToCloud(silent: true));
    }
    _cloudSyncRetryTimer ??= Timer.periodic(_cloudSyncRetryInterval, (_) {
      if (!cloudSyncPending) {
        _cloudSyncRetryTimer?.cancel();
        _cloudSyncRetryTimer = null;
        return;
      }
      if (!cloudSyncBusy && _hasConfiguredSyncTarget()) {
        unawaited(syncToCloud(silent: true));
      }
    });
  }

  void _startCloudAutoPull() {
    if (!_hasConfiguredSyncTarget()) {
      _stopCloudAutoPull();
      return;
    }
    // The timer is now a fallback rather than the primary propagation path.
    // WebSocket notifications trigger forced pulls as soon as another device
    // commits a change to the Worker.
    _configureCloudFallbackPull(realtimeConnected: _cloudSyncLiveSocket != null);
    _startCloudLiveConnection();
    unawaited(syncCloudChangesIfIdle(force: true));
  }

  void _stopCloudAutoPull() {
    _cloudSyncAutoPullTimer?.cancel();
    _cloudSyncAutoPullTimer = null;
    _cloudSyncActivePullInterval = null;
    _lastCloudAutoPullAt = null;
    _cloudRealtimePullPending = false;
    _stopCloudLiveConnection();
  }

  void _configureCloudFallbackPull({required bool realtimeConnected}) {
    if (!_hasConfiguredSyncTarget()) return;
    final interval = realtimeConnected ? _cloudSyncRealtimeFallbackInterval : _cloudSyncDisconnectedFallbackInterval;
    if (_cloudSyncAutoPullTimer != null && _cloudSyncActivePullInterval == interval) return;
    _cloudSyncAutoPullTimer?.cancel();
    _cloudSyncActivePullInterval = interval;
    _cloudSyncAutoPullTimer = Timer.periodic(interval, (_) {
      unawaited(syncCloudChangesIfIdle());
    });
  }

  void _startCloudLiveConnection() {
    if (!_hasConfiguredSyncTarget() || _cloudSyncLiveConnecting || _cloudSyncLiveSocket != null) return;
    _cloudSyncLiveReconnectTimer?.cancel();
    _cloudSyncLiveReconnectTimer = null;
    unawaited(_connectCloudLive());
  }

  Future<void> _connectCloudLive() async {
    if (!_hasConfiguredSyncTarget() || _cloudSyncLiveConnecting || _cloudSyncLiveSocket != null) return;
    _cloudSyncLiveConnecting = true;
    try {
      final socket = await KoinlySyncApi(baseUrl: cloudSyncApiBaseUrl).connectLive(accessToken: syncAccessToken);
      if (!_hasConfiguredSyncTarget()) {
        await socket.close();
        return;
      }
      _cloudSyncLiveSocket = socket;
      _cloudSyncLiveReconnectAttempt = 0;
      _configureCloudFallbackPull(realtimeConnected: true);
      _cloudSyncLiveSubscription = socket.listen(
        _handleCloudLiveMessage,
        onDone: () => _handleCloudLiveClosed(socket),
        onError: (_) => _handleCloudLiveClosed(socket),
        cancelOnError: true,
      );
    } catch (_) {
      _configureCloudFallbackPull(realtimeConnected: false);
      _scheduleCloudLiveReconnect();
    } finally {
      _cloudSyncLiveConnecting = false;
    }
  }

  void _handleCloudLiveMessage(dynamic rawMessage) {
    if (rawMessage is! String) return;
    try {
      final decoded = jsonDecode(rawMessage);
      if (decoded is! Map || decoded['type'] != 'sync-change') return;
      final sourceDeviceId = decoded['deviceId']?.toString() ?? '';
      if (sourceDeviceId.isNotEmpty && sourceDeviceId == syncDeviceId) return;
      if (_syncInProgress || cloudSyncBusy || syncAuthBusy) {
        _cloudRealtimePullPending = true;
        return;
      }
      unawaited(syncCloudChangesIfIdle(force: true));
    } catch (_) {
      // Ignore malformed/non-sync WebSocket messages; the fallback pull timer
      // still guarantees eventual convergence.
    }
  }

  void _handleCloudLiveClosed(WebSocket socket) {
    if (!identical(_cloudSyncLiveSocket, socket)) return;
    _cloudSyncLiveSocket = null;
    final subscription = _cloudSyncLiveSubscription;
    _cloudSyncLiveSubscription = null;
    if (subscription != null) unawaited(subscription.cancel());
    _configureCloudFallbackPull(realtimeConnected: false);
    _scheduleCloudLiveReconnect();
  }

  void _scheduleCloudLiveReconnect() {
    if (!_hasConfiguredSyncTarget() || _cloudSyncLiveReconnectTimer != null) return;
    _cloudSyncLiveReconnectAttempt = math.min(_cloudSyncLiveReconnectAttempt + 1, 7);
    final delaySeconds = math.min(1 << (_cloudSyncLiveReconnectAttempt - 1), 60);
    _cloudSyncLiveReconnectTimer = Timer(Duration(seconds: delaySeconds), () {
      _cloudSyncLiveReconnectTimer = null;
      _startCloudLiveConnection();
    });
  }

  void _restartCloudLiveConnection() {
    if (!_hasConfiguredSyncTarget()) return;
    _stopCloudLiveConnection(resetReconnectAttempt: false);
    _startCloudLiveConnection();
  }

  void _stopCloudLiveConnection({bool resetReconnectAttempt = true}) {
    _cloudSyncLiveReconnectTimer?.cancel();
    _cloudSyncLiveReconnectTimer = null;
    final subscription = _cloudSyncLiveSubscription;
    _cloudSyncLiveSubscription = null;
    if (subscription != null) unawaited(subscription.cancel());
    final socket = _cloudSyncLiveSocket;
    _cloudSyncLiveSocket = null;
    if (socket != null) unawaited(socket.close());
    _cloudSyncLiveConnecting = false;
    if (resetReconnectAttempt) _cloudSyncLiveReconnectAttempt = 0;
  }

  Future<void> syncCloudChangesIfIdle({bool force = false}) async {
    if (!_hasConfiguredSyncTarget() || syncAuthBusy || updateDownloadBusy) return;
    if (_syncInProgress || cloudSyncBusy) return;
    final now = DateTime.now();
    if (!force && _lastCloudAutoPullAt != null && now.difference(_lastCloudAutoPullAt!) < _cloudSyncAutoPullMinimumGap) return;
    _lastCloudAutoPullAt = now;
    await syncToCloud(silent: true);
  }

  void queueCloudSync() {
    if (!_hasConfiguredSyncTarget()) return;
    if (newSyncAccountAwaitingSetupChoice) return;
    _startCloudAutoPull();
    unawaited(_setCloudSyncPending(true));
    _schedulePendingSyncRetry();
    _cloudSyncDebounce?.cancel();
    _cloudSyncDebounce = Timer(_cloudSyncPushDebounce, () {
      unawaited(syncToCloud(silent: true));
    });
  }

  String _cleanSyncError(Object error) {
    final text = error.toString().replaceFirst('Exception: ', '').replaceFirst('Bad state: ', '').trim();
    final lower = text.toLowerCase();
    if (error is TimeoutException || lower.contains('timeoutexception') || lower.contains('future not completed')) {
      return 'Upload timed out. Keep Koinly open on a stronger connection and try again.';
    }
    final redacted = redactSyncSecrets(text);
    return redacted.isEmpty ? 'Sync failed. Check your database configuration.' : redacted;
  }

  @override
  void dispose() {
    _cloudSyncDebounce?.cancel();
    _cloudSyncRetryTimer?.cancel();
    _cloudSyncAutoPullTimer?.cancel();
    _stopCloudLiveConnection();
    _autoBackupTimer?.cancel();
    _updateDownloadClient?.close();
    updateService.close();
    super.dispose();
  }

  Future<CategoryDatabaseMergeResult> _repairDuplicateCategories({bool queueSyncChanges = true}) async {
    final result = await database.mergeDuplicateCategories();
    if (!result.hasChanges) return result;

    var preferencesChanged = false;
    String? remapDefaultCategory(String? id) {
      if (id == null || id.isEmpty) return id;
      final remapped = result.plan.remapCategoryId(id);
      if (remapped != id) preferencesChanged = true;
      return remapped;
    }

    defaultExpenseCategoryId = remapDefaultCategory(defaultExpenseCategoryId);
    defaultIncomeCategoryId = remapDefaultCategory(defaultIncomeCategoryId);
    final remappedFilters = <String>[];
    final seenFilters = <String>{};
    for (final id in filterCategoryIds) {
      final remapped = result.plan.remapCategoryId(id);
      if (remapped != id) preferencesChanged = true;
      if (remapped.isNotEmpty && seenFilters.add(remapped)) remappedFilters.add(remapped);
    }
    if (remappedFilters.length != filterCategoryIds.length) preferencesChanged = true;
    filterCategoryIds = remappedFilters;

    if (preferencesChanged) {
      await prefs.setString('defaultExpenseCategoryId', defaultExpenseCategoryId ?? '');
      await prefs.setString('defaultIncomeCategoryId', defaultIncomeCategoryId ?? '');
      await prefs.setStringList('filterCategoryIds', filterCategoryIds);
    }

    if (queueSyncChanges) {
      final canonicalIds = result.plan.canonicalCategoryIds.toList()..sort();
      for (final categoryId in canonicalIds) {
        await database.enqueueTableRow('categories', categoryId);
      }
      final transactionIds = result.updatedTransactionIds.toList()..sort();
      for (final transactionId in transactionIds) {
        await database.enqueueTableRow('transactions', transactionId);
      }
      final plannedPurchaseIds = result.updatedPlannedPurchaseIds.toList()..sort();
      for (final plannedPurchaseId in plannedPurchaseIds) {
        await database.enqueueTableRow('planned_purchases', plannedPurchaseId);
      }
      final budgetReferences = result.updatedBudgetReferences.toList()
        ..sort((first, second) {
          final byBudget = first.budgetId.compareTo(second.budgetId);
          return byBudget != 0 ? byBudget : first.duplicateCategoryId.compareTo(second.duplicateCategoryId);
        });
      for (final reference in budgetReferences) {
        await database.enqueueTableRow('budget_categories', '${reference.budgetId}:${reference.canonicalCategoryId}');
        await database.enqueueDelete('budget_categories', '${reference.budgetId}:${reference.duplicateCategoryId}');
      }
      final duplicateIds = result.plan.duplicateToCanonicalId.keys.toList()..sort();
      for (final duplicateId in duplicateIds) {
        await database.enqueueDelete('categories', duplicateId);
      }
      if (preferencesChanged) await database.enqueuePreferences(await exportPreferences());
    }
    return result;
  }

  Future<bool> _removeSkippedStarterAccountsIfNeeded({bool force = false, bool allowMixedAccounts = false}) async {
    var shouldRemoveStarterAccounts = force || starterAccountsSkipped;
    if (!shouldRemoveStarterAccounts && onboardingCompleted && await database.hasOnlyUntouchedStarterAccounts()) {
      starterAccountsSkipped = true;
      shouldRemoveStarterAccounts = true;
      await prefs.setBool('starterAccountsSkipped', true);
    }
    if (!shouldRemoveStarterAccounts) return false;

    if (!allowMixedAccounts) {
      final stillHasOnlyUntouchedStarterAccounts = await database.hasOnlyUntouchedStarterAccounts();
      if (!stillHasOnlyUntouchedStarterAccounts) return false;
    }

    final deletedStarterAccountIds = await database.deleteUntouchedStarterAccounts();
    for (final accountId in deletedStarterAccountIds) {
      await database.enqueueDelete('accounts', accountId);
    }
    final remainingAccounts = await database.accounts();
    if (defaultAccountId != null && !remainingAccounts.any((account) => account.id == defaultAccountId)) {
      defaultAccountId = remainingAccounts.where((a) => a.type != AccountType.savings).firstOrNull?.id ?? remainingAccounts.firstOrNull?.id;
      await prefs.setString('defaultAccountId', defaultAccountId ?? '');
    }
    return deletedStarterAccountIds.isNotEmpty;
  }

  Future<void> reload({bool queueSync = false}) async {
    final categoryMerge = await _repairDuplicateCategories();
    if (categoryMerge.hasChanges) queueSync = true;
    if (await _removeSkippedStarterAccountsIfNeeded()) {
      queueSync = true;
    }
    accounts = await database.accounts();
    categories = await database.categories();
    plannedPurchases = await database.plannedPurchases();
    transactions = await database.transactions();
    budgets = await database.budgets();
    loanContacts = await loanRepository.contacts(includeArchived: true);
    loans = await loanRepository.loans();
    loanPayments = await loanRepository.payments();
    _rebuildLookupCaches();
    defaultAccountId ??= accounts.where((a) => a.type != AccountType.savings).firstOrNull?.id ?? accounts.firstOrNull?.id;
    defaultExpenseCategoryId ??= categories.where((c) => c.type == CategoryType.expense).firstOrNull?.id;
    defaultIncomeCategoryId ??= categories.where((c) => c.type == CategoryType.income).firstOrNull?.id;
    notifyListeners();
    unawaited(refreshLoanReminders());
    if (queueSync) queueCloudSync();
  }

  void _rebuildLookupCaches() {
    _accountsById = {for (final account in accounts) account.id: account};
    _categoriesById = {for (final category in categories) category.id: category};
    _loanContactsById = {for (final contact in loanContacts) contact.id: contact};
    _loansById = {for (final loan in loans) loan.id: loan};
    _paymentsByLoan = {for (final loan in loans) loan.id: <LoanPayment>[]};
    for (final payment in loanPayments) {
      _paymentsByLoan.putIfAbsent(payment.loanId, () => <LoanPayment>[]).add(payment);
    }
    for (final payments in _paymentsByLoan.values) {
      payments.sort((a, b) => a.paidOn.compareTo(b.paidOn));
    }
    _operatingAccounts = accounts.where((a) => a.type != AccountType.savings).toList(growable: false);
    _savingAccounts = accounts.where((a) => a.type == AccountType.savings).toList(growable: false);
    _operatingAccountBalance = _operatingAccounts.fold<double>(0, (sum, account) => sum + account.amount);
    _savingAccountBalance = _savingAccounts.fold<double>(0, (sum, account) => sum + account.amount);
    _totalAccountBalance = accounts.fold<double>(0, (sum, account) => sum + account.amount);
    _categoryIdsByType = {
      CategoryType.income: categories.where((c) => c.type == CategoryType.income).map((c) => c.id).toSet(),
      CategoryType.expense: categories.where((c) => c.type == CategoryType.expense).map((c) => c.id).toSet(),
    };

  }

  Future<void> prepareStartNewSetup() async {
    starterAccountsSkipped = false;
    await prefs.setBool('starterAccountsSkipped', false);
    await database.ensureStarterAccountsForNewSetup();
    await reload(queueSync: false);
  }

  Future<bool> discardPreloadedStarterAccountsForImport() async {
    final deletedIds = await database.deletePreloadedStarterAccountsForImport();
    if (deletedIds.isEmpty) return false;

    // If these placeholders were ever synchronized, carry their tombstones
    // into the active merge so a subsequent cloud pull cannot resurrect them.
    if (_hasConfiguredSyncTarget()) {
      for (final accountId in deletedIds) {
        await database.enqueueDelete('accounts', accountId);
      }
    }

    if (defaultAccountId != null && deletedIds.contains(defaultAccountId)) {
      defaultAccountId = null;
      await prefs.setString('defaultAccountId', '');
    }
    accounts = await database.accounts();
    _rebuildLookupCaches();
    notifyListeners();
    return true;
  }

  Future<void> skipStarterAccounts() async {
    starterAccountsSkipped = true;
    await prefs.setBool('starterAccountsSkipped', true);
    final deletedStarterAccountIds = await database.deleteUntouchedStarterAccounts();
    for (final accountId in deletedStarterAccountIds) {
      await database.enqueueDelete('accounts', accountId);
    }
    final remainingAccounts = await database.accounts();
    if (defaultAccountId != null && !remainingAccounts.any((account) => account.id == defaultAccountId)) {
      defaultAccountId = remainingAccounts.where((a) => a.type != AccountType.savings).firstOrNull?.id ?? remainingAccounts.firstOrNull?.id;
      await prefs.setString('defaultAccountId', defaultAccountId ?? '');
    }
    await reload(queueSync: deletedStarterAccountIds.isNotEmpty);
  }

  ThemeMode get themeMode {
    switch (themePreference) {
      case ThemePreference.light:
        return ThemeMode.light;
      case ThemePreference.dark:
        return ThemeMode.dark;
      case ThemePreference.system:
      case ThemePreference.batterySaver:
        return ThemeMode.system;
    }
  }

  Future<void> completeOnboarding() async {
    if (newSyncAccountAwaitingSetupChoice && _hasConfiguredSyncTarget()) {
      await resolveNewSyncAccountWithLocalSetup();
    }
    onboardingCompleted = true;
    if (kIsDesktopApp) {
      desktopSetupVersionCompleted = kRequiredDesktopSetupVersion;
    }
    await prefs.setBool('onboardingCompleted', true);
    if (kIsDesktopApp) {
      await prefs.setInt('desktopSetupVersionCompleted', desktopSetupVersionCompleted);
    }
    notifyListeners();
  }

  Account? accountOf(String id) => _accountsById[id];
  Category? categoryOf(String id) => _categoriesById[id];

  List<Account> get operatingAccounts => _operatingAccounts;
  List<Account> get savingAccounts => _savingAccounts;
  double get operatingAccountBalance => _operatingAccountBalance;
  double get savingAccountBalance => _savingAccountBalance;

  double get totalAccountBalance => _totalAccountBalance;

  String format(double amount) {
    if (amountsHidden) {
      return currencyPosition == CurrencyPosition.prefix ? '$currencySymbol••••' : '••••$currencySymbol';
    }
    final formatter = useSeparators ? _groupedAmountFormatter : _plainAmountFormatter;
    final num = formatter.format(amount.abs());
    final sign = amount < 0 ? '-' : '';
    return currencyPosition == CurrencyPosition.prefix ? '$sign$currencySymbol$num' : '$sign$num$currencySymbol';
  }

  Future<void> toggleAmountsHidden() async {
    amountsHidden = !amountsHidden;
    await prefs.setBool('amountsHidden', amountsHidden);
    notifyListeners();
  }

  Future<void> saveUserProfile({
    required String displayName,
  }) async {
    profileDisplayName = displayName.trim();
    await prefs.setString('profileDisplayName', profileDisplayName);
    notifyListeners();
    await queuePreferenceSync();
  }

  Future<void> replaceProfileMedia({
    required String originalName,
    Uint8List? bytes,
    String? sourcePath,
  }) async {
    final stored = await profileMediaStorage.save(
      originalName: originalName,
      bytes: bytes,
      sourcePath: sourcePath,
    );
    profileMediaPath = stored.path;
    profileMediaOriginalName = stored.originalName;
    profileMediaKind = stored.kind;
    profileMediaSizeBytes = stored.sizeBytes;
    await prefs.setString('profileMediaPath', profileMediaPath);
    await prefs.setString('profileMediaOriginalName', profileMediaOriginalName);
    await prefs.setString('profileMediaKind', profileMediaKind!.name);
    await prefs.setInt('profileMediaSizeBytes', profileMediaSizeBytes);
    profileMediaScale = 1.0;
    profileMediaAlignmentX = 0.0;
    profileMediaAlignmentY = 0.0;
    await prefs.setString('profileMediaScale', '1.0');
    await prefs.setString('profileMediaAlignmentX', '0.0');
    await prefs.setString('profileMediaAlignmentY', '0.0');
    notifyListeners();
  }

  Future<void> saveProfileMediaFraming({
    required double scale,
    required double alignmentX,
    required double alignmentY,
  }) async {
    if (!hasProfileMedia) return;
    profileMediaScale = scale.clamp(1.0, 3.0).toDouble();
    profileMediaAlignmentX = alignmentX.clamp(-1.0, 1.0).toDouble();
    profileMediaAlignmentY = alignmentY.clamp(-1.0, 1.0).toDouble();
    await prefs.setString('profileMediaScale', profileMediaScale.toStringAsFixed(4));
    await prefs.setString('profileMediaAlignmentX', profileMediaAlignmentX.toStringAsFixed(4));
    await prefs.setString('profileMediaAlignmentY', profileMediaAlignmentY.toStringAsFixed(4));
    notifyListeners();
  }

  Future<void> removeProfileMedia() async {
    final previousPath = profileMediaPath;
    profileMediaPath = '';
    profileMediaOriginalName = '';
    profileMediaKind = null;
    profileMediaSizeBytes = 0;
    profileMediaScale = 1.0;
    profileMediaAlignmentX = 0.0;
    profileMediaAlignmentY = 0.0;
    final sharedPreferences = await prefs.prefs;
    await sharedPreferences.remove('profileMediaPath');
    await sharedPreferences.remove('profileMediaOriginalName');
    await sharedPreferences.remove('profileMediaKind');
    await sharedPreferences.remove('profileMediaSizeBytes');
    await sharedPreferences.remove('profileMediaScale');
    await sharedPreferences.remove('profileMediaAlignmentX');
    await sharedPreferences.remove('profileMediaAlignmentY');
    notifyListeners();
    try {
      await WidgetsBinding.instance.endOfFrame;
      await profileMediaStorage.remove(previousPath);
    } catch (_) {
      // The profile is already cleared. A locked stale file is removed during
      // the next media replacement.
    }
  }

  Future<void> dismissFinancialHealthSummary(String key) async {
    if (!dismissedFinancialHealthSummaryKeys.contains(key)) {
      dismissedFinancialHealthSummaryKeys = [...dismissedFinancialHealthSummaryKeys, key];
      await prefs.setStringList('dismissedFinancialHealthSummaryKeys', dismissedFinancialHealthSummaryKeys);
      notifyListeners();
    }
  }

  Future<void> dismissFinancialHealthSummaries(Iterable<String> keys) async {
    final merged = {...dismissedFinancialHealthSummaryKeys, ...keys}.toList();
    dismissedFinancialHealthSummaryKeys = merged;
    await prefs.setStringList('dismissedFinancialHealthSummaryKeys', dismissedFinancialHealthSummaryKeys);
    notifyListeners();
  }

  DateRange activeRange() {
    final now = DateTime.now();
    final startToday = DateTime(now.year, now.month, now.day);
    switch (dateRangeType) {
      case DateRangeType.today:
        return DateRange(startToday, startToday.add(const Duration(days: 1)), 'Today');
      case DateRangeType.thisWeek:
        final start = startToday.subtract(Duration(days: startToday.weekday - 1));
        return DateRange(start, start.add(const Duration(days: 7)), 'This week');
      case DateRangeType.thisMonth:
        final start = DateTime(now.year, now.month, 1);
        final end = DateTime(now.year, now.month + 1, 1);
        return DateRange(start, end, DateFormat('MMMM yyyy').format(start));
      case DateRangeType.thisYear:
        return DateRange(DateTime(now.year), DateTime(now.year + 1), '${now.year}');
      case DateRangeType.allTime:
        return const DateRange(null, null, 'All time');
      case DateRangeType.custom:
        return DateRange(customStart, customEnd?.add(const Duration(days: 1)), 'Custom');
    }
  }

  List<MoneyTransaction> filteredTransactions({String? categoryId, String? accountId, List<MoneyTransactionType>? types, bool ignoreDate = false}) {
    final range = activeRange();
    return transactions.where((tx) {
      if (!ignoreDate) {
        final listOn = tx.listOn;
        if (range.start != null && listOn.isBefore(range.start!)) return false;
        if (range.end != null && !listOn.isBefore(range.end!)) return false;
      }
      if (filterAccountIds.isNotEmpty && !filterAccountIds.contains(tx.fromAccountId) && !(tx.toAccountId != null && filterAccountIds.contains(tx.toAccountId))) return false;
      final isReportableCategoryTransaction = tx.countsAsIncome || tx.countsAsExpense;
      if (filterCategoryIds.isNotEmpty && (!isReportableCategoryTransaction || !filterCategoryIds.contains(tx.categoryId))) return false;
      if (filterTypes.isNotEmpty && !filterTypes.contains(tx.type)) return false;
      if (categoryId != null && (!isReportableCategoryTransaction || tx.categoryId != categoryId)) return false;
      if (accountId != null && tx.fromAccountId != accountId && tx.toAccountId != accountId) return false;
      if (types != null && !types.contains(tx.type)) return false;
      return true;
    }).toList()
      ..sort((a, b) {
        final byListDate = b.listOn.compareTo(a.listOn);
        if (byListDate != 0) return byListDate;
        final byStartDate = b.createdOn.compareTo(a.createdOn);
        return byStartDate != 0 ? byStartDate : b.updatedOn.compareTo(a.updatedOn);
      });
  }

  List<MoneyTransaction> transactionListTransactions() {
    final visible = filteredTransactions();
    if (loanTransactionsVisibleInTransactionList) return visible;
    return visible.where((tx) => !tx.isLoanTransaction).toList();
  }

  Summary summaryFor(List<MoneyTransaction> list) {
    double income = 0, expense = 0;
    for (final tx in list) {
      if (tx.countsAsIncome) income += tx.amount;
      if (tx.countsAsExpense) expense += tx.amount;
    }
    return Summary(income: income, expense: expense);
  }

  Map<String, double> categoryTotals(CategoryType type, {bool ignoreDate = false, List<MoneyTransaction>? source}) {
    final ids = _categoryIdsByType[type] ?? const <String>{};
    final result = <String, double>{};
    for (final tx in source ?? filteredTransactions(ignoreDate: ignoreDate)) {
      if (!ids.contains(tx.categoryId)) continue;
      if (type == CategoryType.income && !tx.countsAsIncome) continue;
      if (type == CategoryType.expense && !tx.countsAsExpense) continue;
      result[tx.categoryId] = (result[tx.categoryId] ?? 0) + tx.amount;
    }
    return result;
  }

  List<BudgetProgress> budgetProgress() {
    final result = <BudgetProgress>[];
    for (final budget in budgets) {
      final start = DateTime(budget.selectedMonth.year, budget.selectedMonth.month, 1);
      final end = DateTime(budget.selectedMonth.year, budget.selectedMonth.month + 1, 1);
      final txs = transactions.where((tx) {
        if (!tx.countsAsExpense) return false;
        if (tx.createdOn.isBefore(start) || !tx.createdOn.isBefore(end)) return false;
        if (!budget.allAccountsSelected && !budget.accountIds.contains(tx.fromAccountId)) return false;
        if (!budget.allCategoriesSelected && !budget.categoryIds.contains(tx.categoryId)) return false;
        return true;
      }).toList();
      result.add(BudgetProgress(budget, txs.fold<double>(0, (sum, tx) => sum + tx.amount), txs));
    }
    return result;
  }

  Future<void> saveTheme(ThemePreference value) async {
    themePreference = value;
    await prefs.setEnum('themePreference', value);
    notifyListeners();
    await queuePreferenceSync();
  }

  Future<void> saveCurrency({required String symbol, required String code, required CurrencyPosition position, required bool separators}) async {
    currencySymbol = symbol;
    currencyCode = code;
    currencyPosition = position;
    useSeparators = separators;
    await prefs.setString('currencySymbol', symbol);
    await prefs.setString('currencyCode', code);
    await prefs.setEnum('currencyPosition', position);
    await prefs.setBool('useSeparators', separators);
    notifyListeners();
    await queuePreferenceSync();
  }

  Future<void> setDateRange(DateRangeType type, {DateTime? start, DateTime? end}) async {
    dateRangeType = type;
    customStart = start;
    customEnd = end;
    await prefs.setEnum('dateRangeType', type);
    await prefs.setString('customStart', start?.toIso8601String() ?? '');
    await prefs.setString('customEnd', end?.toIso8601String() ?? '');
    notifyListeners();
    await queuePreferenceSync();
  }

  Future<void> saveFilters({List<String>? accounts, List<String>? categories, List<MoneyTransactionType>? types}) async {
    filterAccountIds = accounts ?? filterAccountIds;
    filterCategoryIds = categories ?? filterCategoryIds;
    filterTypes = types ?? filterTypes;
    await prefs.setStringList('filterAccountIds', filterAccountIds);
    await prefs.setStringList('filterCategoryIds', filterCategoryIds);
    await prefs.setStringList('filterTypes', filterTypes.map(enumName).toList());
    notifyListeners();
    await queuePreferenceSync();
  }

  Future<void> clearFilters() => saveFilters(accounts: [], categories: [], types: []);

  Future<void> saveDefaults({String? accountId, String? incomeCategoryId, String? expenseCategoryId}) async {
    defaultAccountId = accountId ?? defaultAccountId;
    defaultIncomeCategoryId = incomeCategoryId ?? defaultIncomeCategoryId;
    defaultExpenseCategoryId = expenseCategoryId ?? defaultExpenseCategoryId;
    await prefs.setString('defaultAccountId', defaultAccountId ?? '');
    await prefs.setString('defaultIncomeCategoryId', defaultIncomeCategoryId ?? '');
    await prefs.setString('defaultExpenseCategoryId', defaultExpenseCategoryId ?? '');
    notifyListeners();
    await queuePreferenceSync();
  }

  Future<void> setCompactHome(bool value) async {
    compactHomeSummary = value;
    await prefs.setBool('compactHomeSummary', value);
    notifyListeners();
    await queuePreferenceSync();
  }

  Future<void> setReminder(bool enabled, TimeOfDay time) async {
    reminderEnabled = enabled;
    reminderTime = time;
    await prefs.setBool('reminderEnabled', enabled);
    await prefs.setInt('reminderHour', time.hour);
    await prefs.setInt('reminderMinute', time.minute);
    if (enabled) {
      await ReminderService.scheduleDaily(time);
    } else {
      await ReminderService.cancel();
    }
    notifyListeners();
    await queuePreferenceSync();
  }

  Future<void> queuePreferenceSync() async {
    await database.enqueuePreferences(await exportPreferences());
    queueCloudSync();
  }

  Future<void> saveAccount(Account account) async {
    await database.upsertAccount(account);
    await database.enqueueTableRow('accounts', account.id);
    await reload(queueSync: true);
  }

  Future<void> deleteAccount(String id) async {
    await database.enqueueDelete('accounts', id);
    await database.deleteAccount(id);
    await reload(queueSync: true);
  }

  Future<void> reorderAccounts(List<Account> ordered) async {
    await database.reorderAccounts(ordered);
    for (final account in ordered) {
      await database.enqueueTableRow('accounts', account.id);
    }
    await reload(queueSync: true);
  }

  Future<void> saveCategory(Category category) async {
    await database.upsertCategory(category);
    await database.enqueueTableRow('categories', category.id);
    await reload(queueSync: true);
  }

  Future<void> deleteCategory(String id) async {
    await database.enqueueDelete('categories', id);
    await database.deleteCategory(id);
    await reload(queueSync: true);
  }

  Future<void> savePlannedPurchase(PlannedPurchase item) async {
    await database.upsertPlannedPurchase(item);
    await database.enqueueTableRow('planned_purchases', item.id);
    await reload(queueSync: true);
  }

  Future<void> deletePlannedPurchase(String id) async {
    await database.enqueueDelete('planned_purchases', id);
    await database.deletePlannedPurchase(id);
    await reload(queueSync: true);
  }

  Future<void> purchasePlannedItem(PlannedPurchase item, String accountId) async {
    final transaction = await database.purchasePlannedItem(item, accountId);
    await database.enqueueTableRow('transactions', transaction.id);
    await database.enqueueDelete('planned_purchases', item.id);
    await database.enqueueRowsForTable('accounts');
    await reload(queueSync: true);
  }

  Future<void> addTransaction(MoneyTransaction tx) async {
    await database.addTransaction(tx);
    await database.enqueueTableRow('transactions', tx.id);
    await database.enqueueRowsForTable('accounts');
    await reload(queueSync: true);
  }

  Future<void> updateTransaction(MoneyTransaction tx) async {
    await database.updateTransaction(tx);
    await database.enqueueTableRow('transactions', tx.id);
    await database.enqueueRowsForTable('accounts');
    await reload(queueSync: true);
  }

  Future<void> deleteTransaction(String id) async {
    await database.enqueueDelete('transactions', id);
    await database.deleteTransaction(id);
    await database.enqueueRowsForTable('accounts');
    await reload(queueSync: true);
  }

  Future<void> saveBudget(Budget budget) async {
    final previous = budgets.where((item) => item.id == budget.id).firstOrNull;
    if (previous != null) {
      final removedAccountIds = previous.accountIds.toSet().difference(budget.accountIds.toSet());
      final removedCategoryIds = previous.categoryIds.toSet().difference(budget.categoryIds.toSet());
      for (final accountId in removedAccountIds) {
        await database.enqueueDelete('budget_accounts', '${budget.id}:$accountId');
      }
      for (final categoryId in removedCategoryIds) {
        await database.enqueueDelete('budget_categories', '${budget.id}:$categoryId');
      }
    }
    await database.upsertBudget(budget);
    await database.enqueueTableRow('budgets', budget.id);
    await database.enqueueRowsForTable('budget_accounts', budgetId: budget.id);
    await database.enqueueRowsForTable('budget_categories', budgetId: budget.id);
    await reload(queueSync: true);
  }

  Future<void> deleteBudget(String id) async {
    final previous = budgets.where((item) => item.id == id).firstOrNull;
    if (previous != null) {
      for (final accountId in previous.accountIds) {
        await database.enqueueDelete('budget_accounts', '$id:$accountId');
      }
      for (final categoryId in previous.categoryIds) {
        await database.enqueueDelete('budget_categories', '$id:$categoryId');
      }
    }
    await database.enqueueDelete('budgets', id);
    await database.deleteBudget(id);
    await reload(queueSync: true);
  }


}

// -----------------------------------------------------------------------------
// App shell and shared UI
// -----------------------------------------------------------------------------


class KoinlyApp extends StatelessWidget {
  const KoinlyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final themeMode = context.select<AppController, ThemeMode>((state) => state.themeMode);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      scrollBehavior: const KoinlyScrollBehavior(),
      title: appTitle,
      themeMode: themeMode,
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      home: const StartupGate(),
      builder: (context, child) {
        final media = MediaQuery.of(context);
        final width = media.size.width;
        final maxScale = width < 360 ? 1.04 : width < 600 ? 1.14 : width < 900 ? 1.22 : 1.30;
        return MediaQuery(
          data: media.copyWith(
            textScaler: media.textScaler.clamp(minScaleFactor: .90, maxScaleFactor: maxScale),
            disableAnimations: media.disableAnimations,
          ),
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
  }

  ThemeData _theme(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final baseScheme = ColorScheme.fromSeed(
      seedColor: kSleekAccent,
      brightness: brightness,
    );
    final scheme = isDark
        ? baseScheme.copyWith(
            primary: kSleekAccent,
            onPrimary: Colors.white,
            secondary: kSleekIncome,
            tertiary: const Color(0xFFFF5C7A),
            surface: kSleekSurface,
            surfaceContainerLow: kSleekSurfaceLow,
            surfaceContainer: kSleekSurfaceContainer,
            surfaceContainerHigh: kSleekSurfaceHigh,
            surfaceContainerHighest: kSleekSurfaceHigher,
            background: kSleekBackground,
            outline: kSleekOutline,
            outlineVariant: kSleekOutlineVariant,
          )
        : baseScheme.copyWith(
            primary: kSleekAccent,
            onPrimary: Colors.white,
            secondary: const Color(0xFF0F9F70),
            tertiary: const Color(0xFFFF5074),
            surface: kSleekLightSurface,
            surfaceContainerLow: kSleekLightSurfaceLow,
            surfaceContainer: kSleekLightSurfaceContainer,
            surfaceContainerHigh: kSleekLightSurfaceHigh,
            surfaceContainerHighest: kSleekLightSurfaceHigher,
            background: kSleekLightBackground,
            outline: kSleekLightOutline,
            outlineVariant: kSleekLightOutlineVariant,
          );

    final textTheme = Typography.material2021(platform: TargetPlatform.android).black.apply(
          fontFamily: 'Roboto',
          displayColor: scheme.onSurface,
          bodyColor: scheme.onSurface,
        );

    final pageTransitionBuilder = const KoinlyPageTransitionsBuilder();

    WidgetStateProperty<T> states<T>({required T normal, T? selected, T? pressed, T? disabled}) {
      return WidgetStateProperty.resolveWith((state) {
        if (state.contains(WidgetState.disabled)) return disabled ?? normal;
        if (state.contains(WidgetState.pressed)) return pressed ?? selected ?? normal;
        if (state.contains(WidgetState.selected)) return selected ?? normal;
        return normal;
      });
    }

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.background,
      canvasColor: scheme.background,
      visualDensity: VisualDensity.standard,
      dividerColor: Colors.transparent,
      splashFactory: InkSparkle.splashFactory,
      textTheme: textTheme.copyWith(
        displaySmall: textTheme.displaySmall?.copyWith(fontWeight: FontWeight.w900, letterSpacing: -1.2),
        headlineMedium: textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w900, letterSpacing: -.7),
        titleLarge: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900, letterSpacing: -.2),
        titleMedium: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
        bodyMedium: textTheme.bodyMedium?.copyWith(height: 1.35),
        bodyLarge: textTheme.bodyLarge?.copyWith(height: 1.35),
      ),
      pageTransitionsTheme: PageTransitionsTheme(
        builders: {
          TargetPlatform.android: pageTransitionBuilder,
          TargetPlatform.windows: pageTransitionBuilder,
          TargetPlatform.linux: pageTransitionBuilder,
          TargetPlatform.macOS: pageTransitionBuilder,
          TargetPlatform.iOS: pageTransitionBuilder,
        },
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surface,
        surfaceTintColor: scheme.surfaceTint,
        margin: EdgeInsets.zero,
        shape: AppShapes.squircle(26),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: scheme.surfaceTint,
        shape: RoundedRectangleBorder(borderRadius: AppShapes.dialog),
        titleTextStyle: textTheme.titleLarge?.copyWith(color: scheme.onSurface, fontWeight: FontWeight.w900),
        contentTextStyle: textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant, height: 1.38),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surface,
        surfaceTintColor: scheme.surfaceTint,
        modalBackgroundColor: scheme.surface,
        modalBarrierColor: Colors.black.withOpacity(isDark ? .62 : .36),
        showDragHandle: true,
        dragHandleColor: scheme.outlineVariant,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(kIsDesktopApp ? 34 : 30))),
        constraints: const BoxConstraints(maxWidth: 720),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        elevation: 0,
        backgroundColor: isDark ? kSleekSurfaceHigher : const Color(0xFF0F172A),
        contentTextStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
        shape: RoundedRectangleBorder(borderRadius: AppShapes.medium),
      ),
      listTileTheme: ListTileThemeData(
        minLeadingWidth: 46,
        contentPadding: EdgeInsets.zero,
        shape: AppShapes.squircle(22),
        titleTextStyle: textTheme.titleSmall?.copyWith(color: scheme.onSurface, fontWeight: FontWeight.w900),
        subtitleTextStyle: textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant, fontWeight: FontWeight.w700),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: Colors.transparent,
        elevation: 0,
        indicatorColor: kSleekAccent.withOpacity(isDark ? .26 : .18),
        indicatorShape: AppShapes.squircle(22),
        selectedIconTheme: const IconThemeData(color: kSleekAccent, size: 26),
        unselectedIconTheme: IconThemeData(color: scheme.onSurfaceVariant.withOpacity(.82), size: 24),
        selectedLabelTextStyle: const TextStyle(color: kSleekAccent, fontWeight: FontWeight.w900, fontSize: 12),
        unselectedLabelTextStyle: TextStyle(color: scheme.onSurfaceVariant.withOpacity(.82), fontWeight: FontWeight.w800, fontSize: 11),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: isDark ? const Color(0xE60B1914) : Colors.white.withOpacity(.96),
        indicatorColor: kSleekAccent.withOpacity(isDark ? .24 : .18),
        height: 78,
        elevation: 0,
        shadowColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        labelTextStyle: WidgetStateProperty.resolveWith((state) => TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: state.contains(WidgetState.selected) ? 12 : 11,
              color: state.contains(WidgetState.selected) ? kSleekAccent : scheme.onSurfaceVariant,
            )),
        iconTheme: WidgetStateProperty.resolveWith((state) => IconThemeData(
              color: state.contains(WidgetState.selected) ? kSleekAccent : scheme.onSurfaceVariant.withOpacity(.82),
              size: state.contains(WidgetState.selected) ? 26 : 23,
            )),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? scheme.surfaceContainerHigh.withOpacity(.82) : Colors.white,
        hintStyle: TextStyle(color: scheme.onSurfaceVariant.withOpacity(.78), fontWeight: FontWeight.w600),
        labelStyle: TextStyle(color: scheme.onSurfaceVariant, fontWeight: FontWeight.w700),
        floatingLabelStyle: const TextStyle(color: kSleekAccent, fontWeight: FontWeight.w900),
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        border: OutlineInputBorder(borderRadius: AppShapes.medium, borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(borderRadius: AppShapes.medium, borderSide: BorderSide(color: scheme.outlineVariant.withOpacity(.45), width: 1)),
        focusedBorder: OutlineInputBorder(borderRadius: AppShapes.large, borderSide: BorderSide(color: kSleekAccent.withOpacity(.78), width: 1.4)),
        errorBorder: OutlineInputBorder(borderRadius: AppShapes.medium, borderSide: BorderSide(color: scheme.error.withOpacity(.72), width: 1.2)),
        focusedErrorBorder: OutlineInputBorder(borderRadius: AppShapes.large, borderSide: BorderSide(color: scheme.error, width: 1.4)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: ButtonStyle(
          backgroundColor: states(normal: kSleekAccent, pressed: kSleekAccent.withOpacity(.88), disabled: scheme.onSurface.withOpacity(.12)),
          foregroundColor: states(normal: Colors.white, disabled: scheme.onSurface.withOpacity(.38)),
          overlayColor: WidgetStatePropertyAll(Colors.white.withOpacity(.10)),
          shape: WidgetStateProperty.resolveWith((state) => AppShapes.squircle(state.contains(WidgetState.pressed) ? 22 : 18)),
          padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 22, vertical: 16)),
          minimumSize: const WidgetStatePropertyAll(Size(48, 50)),
          textStyle: const WidgetStatePropertyAll(TextStyle(fontWeight: FontWeight.w900, letterSpacing: -.1)),
          elevation: states(normal: 0.0, pressed: 0.0),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: ButtonStyle(
          foregroundColor: states(normal: kSleekAccent, pressed: kSleekAccent.withOpacity(.75)),
          shape: WidgetStateProperty.resolveWith((state) => AppShapes.squircle(state.contains(WidgetState.pressed) ? 18 : 16)),
          padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 14, vertical: 11)),
          textStyle: const WidgetStatePropertyAll(TextStyle(fontWeight: FontWeight.w900)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: ButtonStyle(
          foregroundColor: states(normal: scheme.onSurface, pressed: kSleekAccent, disabled: scheme.onSurface.withOpacity(.38)),
          side: states(
            normal: BorderSide(color: scheme.outlineVariant.withOpacity(.95), width: 1.2),
            pressed: BorderSide(color: kSleekAccent.withOpacity(.72), width: 1.3),
            disabled: BorderSide(color: scheme.onSurface.withOpacity(.12), width: 1),
          ),
          shape: WidgetStateProperty.resolveWith((state) => AppShapes.squircle(state.contains(WidgetState.pressed) ? 22 : 18)),
          padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 20, vertical: 15)),
          minimumSize: const WidgetStatePropertyAll(Size(48, 50)),
          textStyle: const WidgetStatePropertyAll(TextStyle(fontWeight: FontWeight.w900)),
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((state) => state.contains(WidgetState.selected) ? kSleekAccent.withOpacity(isDark ? .42 : .22) : scheme.surfaceContainerHigh.withOpacity(isDark ? .58 : .72)),
          foregroundColor: WidgetStateProperty.resolveWith((state) => state.contains(WidgetState.selected) ? (isDark ? Colors.white : const Color(0xFF003033)) : scheme.onSurfaceVariant),
          side: WidgetStatePropertyAll(BorderSide(color: scheme.outlineVariant.withOpacity(.9), width: 1.1)),
          shape: WidgetStatePropertyAll(AppShapes.squircle(22)),
          textStyle: const WidgetStatePropertyAll(TextStyle(fontWeight: FontWeight.w900)),
          padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(vertical: 14, horizontal: 16)),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: kSleekAccent,
        foregroundColor: Colors.white,
        elevation: 6,
        highlightElevation: 2,
        shape: AppShapes.squircle(22),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((state) => state.contains(WidgetState.pressed) ? kSleekAccent.withOpacity(.16) : (isDark ? scheme.surfaceContainerHigh.withOpacity(.72) : Colors.white.withOpacity(.92))),
          foregroundColor: WidgetStateProperty.resolveWith((state) => state.contains(WidgetState.pressed) ? kSleekAccent : scheme.onSurface),
          shape: WidgetStateProperty.resolveWith((state) => AppShapes.squircle(state.contains(WidgetState.pressed) ? 18 : 16)),
          minimumSize: const WidgetStatePropertyAll(Size(44, 44)),
        ),
      ),
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        iconTheme: IconThemeData(color: scheme.onSurface),
        titleTextStyle: textTheme.headlineSmall?.copyWith(color: scheme.onSurface, fontWeight: FontWeight.w900, letterSpacing: -.6),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: scheme.surfaceContainerHigh,
        selectedColor: kSleekAccent.withOpacity(isDark ? .34 : .22),
        disabledColor: scheme.onSurface.withOpacity(.08),
        side: BorderSide(color: scheme.outlineVariant.withOpacity(.92)),
        shape: AppShapes.squircle(18),
        labelStyle: TextStyle(color: scheme.onSurface, fontWeight: FontWeight.w800),
        secondaryLabelStyle: const TextStyle(color: kSleekAccent, fontWeight: FontWeight.w900),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(color: kSleekAccent, linearTrackColor: Color(0x3310B981)),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((state) => state.contains(WidgetState.selected) ? Colors.white : scheme.outline),
        trackColor: WidgetStateProperty.resolveWith((state) => state.contains(WidgetState.selected) ? kSleekAccent : scheme.surfaceContainerHighest),
        trackOutlineColor: WidgetStatePropertyAll(scheme.outlineVariant),
      ),
    );
  }
}

class StartupGate extends StatelessWidget {
  const StartupGate({super.key});

  @override
  Widget build(BuildContext context) {
    final gate = context.select<AppController, ({bool loading, bool setupCompleted})>(
      (state) => (loading: state.loading, setupCompleted: state.setupCompletedForCurrentPlatform),
    );
    if (gate.loading) return const SplashScreen();
    return gate.setupCompleted
        ? const FinancialHealthReviewGate(child: MainShell())
        : const OnboardingScreen();
  }
}


class FinancialHealthReviewGate extends StatefulWidget {
  const FinancialHealthReviewGate({super.key, required this.child});

  final Widget child;

  @override
  State<FinancialHealthReviewGate> createState() => _FinancialHealthReviewGateState();
}

class _FinancialHealthReviewGateState extends State<FinancialHealthReviewGate> {
  bool _scheduled = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_scheduled) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final state = context.read<AppController>();
      final prompts = pendingFinancialHealthReviewPrompts(state);
      if (prompts.isEmpty) return;
      await showKoinlyPopup<void>(
        context,
        maxWidth: 680,
        maxHeight: 800,
        barrierDismissible: false,
        child: FinancialHealthReviewDialog(prompts: prompts),
      );
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class FinancialHealthReviewPrompt {
  const FinancialHealthReviewPrompt({required this.period, required this.selectedDate});

  final FinancialHealthPeriod period;
  final DateTime selectedDate;

  String get key => financialHealthSummaryKey(period, selectedDate);
  String get label => financialPeriodLabel(period, selectedDate);
  String get title => period == FinancialHealthPeriod.monthly ? 'Monthly Summary Ready' : 'Yearly Summary Ready';
  String get subtitle => period == FinancialHealthPeriod.monthly ? '$label has ended. Review your financial health.' : '$label has ended. Review your yearly financial health.';
}

String financialHealthSummaryKey(FinancialHealthPeriod period, DateTime selectedDate) {
  return period == FinancialHealthPeriod.monthly ? "monthly:${DateFormat('yyyy-MM').format(selectedDate)}" : "yearly:${selectedDate.year}";
}

List<FinancialHealthReviewPrompt> pendingFinancialHealthReviewPrompts(AppController state, [DateTime? date]) {
  final now = date ?? DateTime.now();
  final prompts = <FinancialHealthReviewPrompt>[
    FinancialHealthReviewPrompt(period: FinancialHealthPeriod.monthly, selectedDate: DateTime(now.year, now.month - 1, 1)),
    FinancialHealthReviewPrompt(period: FinancialHealthPeriod.yearly, selectedDate: DateTime(now.year - 1, 1, 1)),
  ];

  return prompts.where((prompt) {
    if (state.dismissedFinancialHealthSummaryKeys.contains(prompt.key)) return false;
    return financialHealthSummaryHasActivity(state, prompt);
  }).toList();
}

bool financialHealthSummaryHasActivity(AppController state, FinancialHealthReviewPrompt prompt) {
  final summary = FinancialHealthSummary.build(state, period: prompt.period, selectedDate: prompt.selectedDate);
  return summary.income > 0 ||
      summary.expense > 0 ||
      summary.savingsIn > 0 ||
      summary.savingsOut > 0 ||
      summary.billPaymentCount > 0 ||
      summary.billUnpaidCount > 0 ||
      summary.billUpcomingCount > 0 ||
      summary.billOverdueCount > 0 ||
      summary.budgetItems.isNotEmpty;
}

class FinancialHealthReviewDialog extends StatefulWidget {
  const FinancialHealthReviewDialog({super.key, required this.prompts});

  final List<FinancialHealthReviewPrompt> prompts;

  @override
  State<FinancialHealthReviewDialog> createState() => _FinancialHealthReviewDialogState();
}

class _FinancialHealthReviewDialogState extends State<FinancialHealthReviewDialog> {
  late final PageController _pageController;
  int _index = 0;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _skipAll() async {
    if (_busy) return;
    setState(() => _busy = true);
    final state = context.read<AppController>();
    await state.dismissFinancialHealthSummaries(widget.prompts.map((prompt) => prompt.key));
    if (mounted) Navigator.pop(context);
  }

  Future<void> _continue() async {
    if (_busy) return;
    setState(() => _busy = true);
    final state = context.read<AppController>();
    await state.dismissFinancialHealthSummary(widget.prompts[_index].key);
    if (!mounted) return;
    if (_index >= widget.prompts.length - 1) {
      Navigator.pop(context);
      return;
    }
    setState(() {
      _busy = false;
      _index += 1;
    });
    await _pageController.animateToPage(_index, duration: AppMotion.medium, curve: AppMotion.emphasized);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppController>();
    final prompt = widget.prompts[_index];
    final last = _index >= widget.prompts.length - 1;

    return SizedBox(
      height: 760,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 10),
            child: Row(
              children: [
                iconBubble(context, prompt.period == FinancialHealthPeriod.monthly ? 'month' : 'year', prompt.period == FinancialHealthPeriod.monthly ? kSleekAccentHex : '#FBC879', size: 48),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(prompt.title, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
                      Text(prompt.subtitle, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: kSleekMuted, fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
                if (widget.prompts.length > 1)
                  Chip(
                    label: Text('${_index + 1}/${widget.prompts.length}'),
                    avatar: const Icon(Icons.auto_stories_rounded, size: 17),
                  ),
              ],
            ),
          ),
          Expanded(
            child: PageView.builder(
              controller: _pageController,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: widget.prompts.length,
              itemBuilder: (context, index) {
                final item = widget.prompts[index];
                final summary = FinancialHealthSummary.build(state, period: item.period, selectedDate: item.selectedDate);
                return KoinlyPopupContent(
                  padding: const EdgeInsets.fromLTRB(18, 4, 18, 8),
                  child: FinancialHealthSummarySection(summary: summary),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 18),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : _skipAll,
                    icon: const Icon(Icons.skip_next_rounded),
                    label: const Text('Skip all'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _busy ? null : _continue,
                    icon: Icon(last ? Icons.done_rounded : Icons.arrow_forward_rounded),
                    label: Text(last ? 'Done' : 'Next'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 88,
              height: 104,
              child: Image.asset(
                'assets/icons/koinly_mark.png',
                fit: BoxFit.contain,
                filterQuality: FilterQuality.high,
              ),
            ),
            const SizedBox(height: 24),
            Text(appTitle, style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w900)),
            const SizedBox(height: 16),
            const KoinlyInlineLoader(size: 28),
          ],
        ),
      ),
    );
  }
}

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> with WidgetsBindingObserver {
  static const Duration _startupUpdateCheckDelay = Duration(milliseconds: 1400);
  static const Duration _automaticUpdateCheckInterval = Duration(minutes: 15);
  static const Duration _automaticUpdateRetryDelay = Duration(seconds: 30);
  static const Duration _blockedUpdatePromptRetryDelay = Duration(seconds: 8);

  bool _automaticUpdateCheckInFlight = false;
  Timer? _automaticUpdateRetryTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduleAutomaticUpdateCheck(delay: _startupUpdateCheckDelay);
    });
  }

  @override
  void dispose() {
    _automaticUpdateRetryTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      final controller = context.read<AppController>();
      unawaited(controller.resumePendingAndroidInstallIfAllowed());
      unawaited(controller.syncCloudChangesIfIdle(force: true));
      unawaited(controller.refreshLoanReminders());
      unawaited(controller.runAutomaticBackupIfDue());
      _scheduleAutomaticUpdateCheck();
    }
  }

  void _scheduleAutomaticUpdateCheck({Duration delay = Duration.zero}) {
    if (!mounted || _automaticUpdateRetryTimer?.isActive == true) return;
    if (delay == Duration.zero) {
      unawaited(_runAutomaticUpdateCheck());
      return;
    }
    _automaticUpdateRetryTimer = Timer(delay, () {
      _automaticUpdateRetryTimer = null;
      unawaited(_runAutomaticUpdateCheck());
    });
  }

  Future<void> _runAutomaticUpdateCheck() async {
    if (_automaticUpdateCheckInFlight || !mounted) return;
    final state = context.read<AppController>();
    final lastCheckedAt = state.updateLastCheckedAt;
    final checkedRecently = lastCheckedAt != null && DateTime.now().difference(lastCheckedAt) < _automaticUpdateCheckInterval;
    final canRetryRecentFailure = checkedRecently && _shouldRetryAutomaticUpdateCheck(state.updateCheckOutcome);
    if (checkedRecently && !canRetryRecentFailure) {
      final release = state.latestGithubRelease;
      if (state.hasAvailableUpdate && release != null) {
        await _showAutomaticUpdateDialogIfReady(state, release);
      }
      return;
    }

    _automaticUpdateCheckInFlight = true;
    try {
      final result = await state.checkForUpdates();
      if (!mounted) return;
      if (result.hasUpdate && result.release != null) {
        if (state.automaticUpdatePopupEnabled) {
          await UpdateBackgroundService.notifyReleaseIfNeeded(result.release!);
        }
        await _showAutomaticUpdateDialogIfReady(state, result.release!);
      } else if (_shouldRetryAutomaticUpdateCheck(result.outcome)) {
        _scheduleAutomaticUpdateCheck(delay: _automaticUpdateRetryDelay);
      }
    } finally {
      _automaticUpdateCheckInFlight = false;
    }
  }

  bool _shouldRetryAutomaticUpdateCheck(UpdateCheckOutcome outcome) {
    return outcome == UpdateCheckOutcome.networkError ||
        outcome == UpdateCheckOutcome.httpError;
  }

  Future<void> _showAutomaticUpdateDialogIfReady(AppController state, GithubRelease release) async {
    if (!mounted || !state.automaticUpdatePopupEnabled || !state.canShowStartupUpdateDialog(release)) return;
    final route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) {
      _scheduleAutomaticUpdateCheck(delay: _blockedUpdatePromptRetryDelay);
      return;
    }
    state.markStartupUpdateDialogShown(release);
    await showUpdateBottomSheet(context);
  }

  @override
  Widget build(BuildContext context) {
    final requestedTabIndex = context.select<AppController, int>((state) => state.tabIndex);
    final state = context.read<AppController>();
    final pages = <Widget>[
      const HomeDashboardScreen(),
      const AnalysisScreen(),
      const LoansScreen(),
      const TransactionListScreen(),
      const CategoriesScreen(),
    ];
    final tabIndex = requestedTabIndex.clamp(0, pages.length - 1).toInt();
    if (requestedTabIndex != tabIndex) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) state.selectTabIndex(tabIndex);
      });
    }

    final Widget? actionButton = tabIndex == kTransactionTabIndex
        ? MotionTouchFeedback(
            scale: .958,
            child: FloatingActionButton.extended(
            heroTag: 'transactionAddFab',
            onPressed: () {
              AppMotion.actionHaptic(context);
              showTransactionEditor(context);
            },
            icon: const Icon(Icons.add_rounded),
              label: const Text('Add'),
            ),
          )
        : null;
    final Widget? planButton = tabIndex == kTransactionTabIndex
        ? SizedBox(
            width: 128,
            child: MotionTouchFeedback(
              scale: .958,
              child: FloatingActionButton.extended(
              heroTag: 'transactionPlanFab',
              onPressed: () {
                AppMotion.actionHaptic(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const PurchasePlanScreen()),
                );
              },
              icon: const Icon(Icons.event_note_rounded),
                label: const Text('Plan'),
              ),
            ),
          )
        : null;

    return LayoutBuilder(
      builder: (context, constraints) {
        final useDesktopNavigation = constraints.maxWidth >= 900;
        final extendDesktopNavigation = constraints.maxWidth >= 1180;

        void selectTab(int index) {
          if (index == tabIndex) return;
          AppMotion.selectionHaptic(context);
          state.selectTabIndex(index);
        }

        return Scaffold(
          extendBody: !useDesktopNavigation,
          body: Row(
            children: [
              if (useDesktopNavigation)
                _SideRailNavigation(
                  selectedIndex: tabIndex,
                  extended: extendDesktopNavigation,
                  onSelected: selectTab,
                ),
              Expanded(
                child: AnimatedSwitcher(
                  duration: AppMotion.medium,
                  switchInCurve: AppMotion.emphasized,
                  switchOutCurve: AppMotion.emphasizedAccelerate,
                  transitionBuilder: (child, animation) {
                    final scale = Tween<double>(begin: .988, end: 1).animate(animation);
                    return FadeTransition(
                      opacity: animation,
                      child: ScaleTransition(scale: scale, child: child),
                    );
                  },
                  child: KeyedSubtree(
                    key: ValueKey<int>(tabIndex),
                    child: Stack(
                      children: [
                        Positioned.fill(child: pages[tabIndex]),
                        if (planButton != null)
                          Positioned(
                            left: useDesktopNavigation
                                ? 34
                                : math.max(20.0, constraints.maxWidth * .247 - 64.0),
                            bottom: MediaQuery.of(context).padding.bottom + (useDesktopNavigation ? 30 : 102),
                            child: planButton,
                          ),
                        if (actionButton != null)
                          Positioned(
                            right: useDesktopNavigation ? 34 : 28,
                            bottom: MediaQuery.of(context).padding.bottom + (useDesktopNavigation ? 30 : 102),
                            child: actionButton,
                          ),
                        if (!useDesktopNavigation)
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 0,
                            child: _FloatingDockNavigation(
                              selectedIndex: tabIndex,
                              onSelected: selectTab,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _DockDestination {
  const _DockDestination({
    required this.label,
    required this.icon,
    required this.activeIcon,
  });

  final String label;
  final IconData icon;
  final IconData activeIcon;
}

class _SideRailNavigation extends StatelessWidget {
  const _SideRailNavigation({
    required this.selectedIndex,
    required this.extended,
    required this.onSelected,
  });

  final int selectedIndex;
  final bool extended;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final borderColor = dark ? Colors.white.withOpacity(.06) : scheme.outline.withOpacity(.14);
    final railColor = dark ? kSleekSurfaceLow : Colors.white;

    return Material(
      color: railColor,
      child: SafeArea(
        right: false,
        child: Container(
          width: extended ? 238 : 92,
          decoration: BoxDecoration(
            border: Border(right: BorderSide(color: borderColor, width: 1)),
            boxShadow: kIsDesktopApp
                ? null
                : [
                    BoxShadow(
                      color: Colors.black.withOpacity(dark ? .18 : .035),
                      blurRadius: 18,
                      offset: const Offset(6, 0),
                    ),
                  ],
          ),
          child: Column(
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(extended ? 20 : 14, 18, extended ? 20 : 14, 10),
                child: Row(
                  mainAxisAlignment: extended ? MainAxisAlignment.start : MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 46,
                      height: 46,
                      child: Image.asset(
                        'assets/icons/koinly_mark.png',
                        fit: BoxFit.contain,
                        filterQuality: FilterQuality.high,
                      ),
                    ),
                    if (extended) ...[
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(appTitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
                            Text('Desktop', style: Theme.of(context).textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant, fontWeight: FontWeight.w800)),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Expanded(
                child: NavigationRail(
                  selectedIndex: selectedIndex,
                  extended: extended,
                  minWidth: 92,
                  minExtendedWidth: 238,
                  groupAlignment: -0.86,
                  backgroundColor: Colors.transparent,
                  indicatorColor: kSleekAccent.withOpacity(dark ? .26 : .16),
                  labelType: extended ? NavigationRailLabelType.none : NavigationRailLabelType.all,
                  selectedIconTheme: const IconThemeData(color: kSleekAccent, size: 26),
                  unselectedIconTheme: IconThemeData(color: scheme.onSurfaceVariant.withOpacity(.82), size: 24),
                  selectedLabelTextStyle: const TextStyle(color: kSleekAccent, fontWeight: FontWeight.w900, fontSize: 12),
                  unselectedLabelTextStyle: TextStyle(color: scheme.onSurfaceVariant.withOpacity(.82), fontWeight: FontWeight.w800, fontSize: 11),
                  onDestinationSelected: onSelected,
                  destinations: _FloatingDockNavigation.destinations
                      .map(
                        (destination) => NavigationRailDestination(
                          icon: MotionTouchFeedback(
                            scale: .94,
                            child: Icon(destination.icon),
                          ),
                          selectedIcon: MotionTouchFeedback(
                            scale: .94,
                            child: Icon(destination.activeIcon),
                          ),
                          label: MotionTouchFeedback(
                            scale: .97,
                            child: Text(destination.label, maxLines: 1, overflow: TextOverflow.ellipsis),
                          ),
                        ),
                      )
                      .toList(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FloatingDockNavigation extends StatelessWidget {
  const _FloatingDockNavigation({
    required this.selectedIndex,
    required this.onSelected,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelected;

  static List<_DockDestination> get destinations => [
    const _DockDestination(label: 'Home', icon: Icons.home_outlined, activeIcon: Icons.home_rounded),
    const _DockDestination(label: 'Analysis', icon: Icons.insights_outlined, activeIcon: Icons.insights_rounded),
    const _DockDestination(label: 'Loans', icon: Icons.currency_exchange_outlined, activeIcon: Icons.currency_exchange_rounded),
    const _DockDestination(label: 'Transaction', icon: Icons.receipt_long_outlined, activeIcon: Icons.receipt_long_rounded),
    const _DockDestination(label: 'Categories', icon: Icons.category_outlined, activeIcon: Icons.category_rounded),
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final active = kSleekAccent;
    final inactive = dark ? scheme.onSurface.withOpacity(.72) : scheme.onSurfaceVariant.withOpacity(.78);
    final dockColor = dark ? const Color(0xF20B1914) : Colors.white.withOpacity(.94);
    final selectedColor = dark ? kSleekAccent.withOpacity(.32) : kSleekAccent.withOpacity(.18);

    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(18, 0, 18, 14),
      child: Center(
        heightFactor: 1,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 450),
          child: Container(
            height: 78,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            decoration: BoxDecoration(
              color: dockColor,
              gradient: dark
                  ? LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        kSleekSurfaceHigh.withOpacity(.94),
                        kSleekSurfaceLow.withOpacity(.96),
                      ],
                    )
                  : null,
              borderRadius: BorderRadius.circular(30),
              border: Border.all(color: dark ? Colors.white.withOpacity(.095) : scheme.outline.withOpacity(.16), width: 1),
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(dark ? .42 : .12), blurRadius: 28, offset: const Offset(0, 14)),
                BoxShadow(color: kSleekAccent.withOpacity(dark ? .12 : .05), blurRadius: 28, offset: const Offset(0, -3)),
              ],
            ),
            child: Row(
              children: List.generate(destinations.length, (index) {
                final destination = destinations[index];
                final selected = selectedIndex == index;
                return Expanded(
                  child: Tooltip(
                    message: destination.label,
                    child: Semantics(
                      selected: selected,
                      button: true,
                      label: destination.label,
                      child: MotionInkWell(
                        borderRadius: BorderRadius.circular(22),
                        onTap: () => onSelected(index),
                        child: Center(
                          child: AnimatedContainer(
                            duration: AppMotion.fast,
                            curve: AppMotion.spring,
                            width: selected ? 58 : 48,
                            height: selected ? 58 : 48,
                            decoration: BoxDecoration(
                              color: selected ? selectedColor : Colors.transparent,
                              borderRadius: BorderRadius.circular(selected ? 21 : 18),
                              border: selected ? Border.all(color: kSleekAccent.withOpacity(.32), width: 1) : null,
                              boxShadow: selected
                                  ? [BoxShadow(color: kSleekAccent.withOpacity(.20), blurRadius: 18, offset: const Offset(0, 8))]
                                  : null,
                            ),
                            child: Icon(
                              selected ? destination.activeIcon : destination.icon,
                              color: selected ? active : inactive,
                              size: selected ? 28 : 26,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
        ),
      ),
    );
  }
}


class _KeyboardDismissOnBack extends StatelessWidget {
  const _KeyboardDismissOnBack({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final keyboardVisible = MediaQuery.viewInsetsOf(context).bottom > 0;

    // Keep Android back/predictive-back keyboard-first everywhere text input
    // can appear. The first back action only clears focus/dismisses the IME;
    // after the insets close, the next back action can pop the route normally.
    return PopScope<Object?>(
      canPop: !keyboardVisible,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop || !keyboardVisible) return;
        FocusManager.instance.primaryFocus?.unfocus();
      },
      child: child,
    );
  }
}

class PageScaffold extends StatelessWidget {
  const PageScaffold({super.key, required this.title, this.actions = const [], required this.child, this.subtitle});
  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final small = AppBreakpoints.isSmall(context);
    final desktop = AppBreakpoints.isExpanded(context);
    return _KeyboardDismissOnBack(
      child: Scaffold(
        backgroundColor: scheme.background,
        appBar: AppBar(
          toolbarHeight: desktop ? 76 : small ? 68 : 76,
          titleSpacing: small ? 12 : 18,
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).appBarTheme.titleTextStyle?.copyWith(fontSize: desktop ? 26 : small ? 23 : 27)),
              if (subtitle != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant, fontWeight: FontWeight.w700)),
                ),
            ],
          ),
          actions: actions
              .map((action) => Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: action,
                  ))
              .toList(),
        ),
        body: KoinlyAtmosphere(child: SafeArea(top: false, child: child)),
      ),
    );
  }
}

class KoinlyAtmosphere extends StatelessWidget {
  const KoinlyAtmosphere({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    if (!dark) {
      return DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFF8FBF8), Color(0xFFEEF6F1), Color(0xFFFFFFFF)],
          ),
        ),
        child: child,
      );
    }

    return DecoratedBox(
      decoration: const BoxDecoration(
        color: kSleekBackground,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF071711), kSleekBackground, Color(0xFF091914)],
        ),
      ),
      child: child,
    );
  }
}

class ResponsiveContent extends StatelessWidget {
  const ResponsiveContent({
    super.key,
    required this.child,
    this.padding,
    this.mobileMaxWidth = 720,
    this.desktopMaxWidth = 1180,
  });

  final Widget child;
  final EdgeInsets? padding;
  final double mobileMaxWidth;
  final double desktopMaxWidth;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final screenWidth = MediaQuery.sizeOf(context).width;
        final small = screenWidth < AppBreakpoints.compact;
        final medium = screenWidth >= AppBreakpoints.medium;
        final desktop = screenWidth >= AppBreakpoints.expanded;
        final large = screenWidth >= AppBreakpoints.large;
        final maxContentWidth = desktop ? (large ? desktopMaxWidth : math.min(desktopMaxWidth, 1040.0)) : (medium ? mobileMaxWidth : constraints.maxWidth);
        final double width = math.min(constraints.maxWidth, maxContentWidth).toDouble();
        final resolvedPadding = padding ??
            EdgeInsets.fromLTRB(
              desktop ? 32 : small ? 12 : 16,
              desktop ? 22 : small ? 6 : 8,
              desktop ? 32 : small ? 12 : 16,
              desktop ? 42 : small ? 96 : 110,
            );

        return Align(
          alignment: Alignment.topCenter,
          child: SizedBox(
            width: width,
            child: ListView(
              padding: resolvedPadding,
              physics: optimizedScrollPhysics(context),
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              cacheExtent: kIsDesktopApp ? 900 : 320,
              children: [RepaintBoundary(child: child)],
            ),
          ),
        );
      },
    );
  }
}


class ResponsiveListContent extends StatelessWidget {
  const ResponsiveListContent({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    this.header = const [],
    this.empty,
    this.padding,
    this.mobileMaxWidth = 720,
    this.desktopMaxWidth = 1180,
    this.itemSpacing = 10,
  });

  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final List<Widget> header;
  final Widget? empty;
  final EdgeInsets? padding;
  final double mobileMaxWidth;
  final double desktopMaxWidth;
  final double itemSpacing;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final screenWidth = MediaQuery.sizeOf(context).width;
        final small = screenWidth < AppBreakpoints.compact;
        final medium = screenWidth >= AppBreakpoints.medium;
        final desktop = screenWidth >= AppBreakpoints.expanded;
        final large = screenWidth >= AppBreakpoints.large;
        final maxContentWidth = desktop ? (large ? desktopMaxWidth : math.min(desktopMaxWidth, 1040.0)) : (medium ? mobileMaxWidth : constraints.maxWidth);
        final double width = math.min(constraints.maxWidth, maxContentWidth).toDouble();
        final resolvedPadding = padding ??
            EdgeInsets.fromLTRB(
              desktop ? 32 : small ? 12 : 16,
              desktop ? 22 : small ? 6 : 8,
              desktop ? 32 : small ? 12 : 16,
              desktop ? 42 : small ? 96 : 110,
            );
        final bodyCount = itemCount == 0 && empty != null ? 1 : itemCount;

        return Align(
          alignment: Alignment.topCenter,
          child: SizedBox(
            width: width,
            child: SlidableAutoCloseBehavior(
              closeWhenOpened: true,
              closeWhenTapped: true,
              child: ListView.builder(
                padding: resolvedPadding,
                physics: optimizedScrollPhysics(context),
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                cacheExtent: kIsDesktopApp ? 620 : 420,
                addAutomaticKeepAlives: false,
                addSemanticIndexes: false,
                itemCount: header.length + bodyCount,
                itemBuilder: (context, index) {
                  if (index < header.length) return header[index];
                  final bodyIndex = index - header.length;
                  if (itemCount == 0) return empty!;
                  return Padding(
                    padding: EdgeInsets.only(bottom: itemSpacing),
                    child: itemBuilder(context, bodyIndex),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }
}


class _KoinlySlidableAction extends StatelessWidget {
  const _KoinlySlidableAction({
    required this.onPressed,
    required this.backgroundColor,
    required this.foregroundColor,
    required this.icon,
    required this.label,
  });

  final SlidableActionCallback onPressed;
  final Color backgroundColor;
  final Color foregroundColor;
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    // Use flutter_slidable's native action surface rather than nesting a
    // rounded box inside a transparent CustomSlidableAction. The nested
    // version could be clipped to a colored sliver while a drag was between
    // snap points. Native actions keep a stable action width throughout the
    // gesture and clip their own content correctly.
    return SlidableAction(
      autoClose: true,
      onPressed: onPressed,
      backgroundColor: backgroundColor,
      foregroundColor: foregroundColor,
      icon: icon,
      label: label,
      spacing: 4,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      borderRadius: BorderRadius.circular(18),
    );
  }
}

class ExpressiveCard extends StatelessWidget {
  const ExpressiveCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.color,
    this.radius = 26,
    this.surfaceTint = true,
  });

  final Widget child;
  final EdgeInsets padding;
  final Color? color;
  final double radius;
  final bool surfaceTint;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final reducedMotion = MediaQuery.of(context).disableAnimations;
    final lightweightEffects = kLowEndFriendlyUi || kIsDesktopApp;
    final baseColor = color ?? (dark ? scheme.surfaceContainer : Colors.white);
    final borderColor = dark ? Colors.white.withOpacity(.085) : scheme.outlineVariant.withOpacity(.74);
    final decoration = BoxDecoration(
      color: baseColor.withOpacity(dark ? .88 : 1),
      gradient: surfaceTint && !reducedMotion && !lightweightEffects
          ? LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color.alphaBlend(kSleekAccent.withOpacity(dark ? .075 : .030), baseColor),
                baseColor.withOpacity(dark ? .92 : 1),
                Color.alphaBlend(scheme.tertiary.withOpacity(dark ? .035 : .022), baseColor),
              ],
            )
          : null,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: borderColor, width: 1),
      boxShadow: (reducedMotion || lightweightEffects)
          ? [
              if (!kIsDesktopApp) BoxShadow(color: Colors.black.withOpacity(dark ? .20 : .035), blurRadius: 10, offset: const Offset(0, 5)),
            ]
          : [
              if (dark)
                BoxShadow(color: Colors.black.withOpacity(.32), blurRadius: 22, offset: const Offset(0, 12))
              else
                BoxShadow(color: scheme.shadow.withOpacity(.060), blurRadius: 18, offset: const Offset(0, 9)),
              if (dark) BoxShadow(color: kSleekAccent.withOpacity(.06), blurRadius: 26, offset: const Offset(0, 4)),
            ],
    );
    final cardChild = ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Padding(padding: padding, child: child),
    );
    if (reducedMotion) {
      return Container(decoration: decoration, child: cardChild);
    }
    return AnimatedContainer(
      duration: AppMotion.medium,
      curve: AppMotion.emphasized,
      decoration: decoration,
      child: cardChild,
    );
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.trailing});
  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 22, 4, 10),
      child: Row(
        children: [
          Expanded(child: Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900, letterSpacing: -.2))),
          if (trailing != null) DefaultTextStyle.merge(style: TextStyle(color: scheme.primary, fontWeight: FontWeight.w800), child: trailing!),
        ],
      ),
    );
  }
}


class SleekPillOption<T> {
  const SleekPillOption({required this.value, required this.label, this.icon});
  final T value;
  final String label;
  final IconData? icon;
}

class SleekPillSelector<T> extends StatelessWidget {
  const SleekPillSelector({
    super.key,
    required this.options,
    required this.selected,
    required this.onChanged,
  });

  final List<SleekPillOption<T>> options;
  final T selected;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < options.length; i++) ...[
          Expanded(
            child: _SleekPillButton<T>(
              option: options[i],
              selected: options[i].value == selected,
              onTap: () => onChanged(options[i].value),
            ),
          ),
          if (i != options.length - 1) const SizedBox(width: 8),
        ],
      ],
    );
  }
}

class SleekCyclePillSelector<T> extends StatelessWidget {
  const SleekCyclePillSelector({
    super.key,
    required this.options,
    required this.selected,
    required this.onChanged,
  });

  final List<SleekPillOption<T>> options;
  final T selected;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final selectedIndex = options.indexWhere((option) => option.value == selected);
    final currentIndex = selectedIndex < 0 ? 0 : selectedIndex;
    final current = options[currentIndex];
    final next = options[(currentIndex + 1) % options.length];
    final selectedColor = kSleekAccent.withOpacity(.32);
    final textColor = Theme.of(context).colorScheme.onSurface;
    final mutedColor = Theme.of(context).colorScheme.onSurface.withOpacity(.60);

    return MotionPressable(
      onTap: () => onChanged(next.value),
      borderRadius: AppShapes.medium,
      child: Material(
        color: selectedColor,
        borderRadius: AppShapes.medium,
        child: AnimatedContainer(
          duration: AppMotion.fast,
          curve: AppMotion.emphasized,
          constraints: const BoxConstraints(minHeight: 64),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: AppShapes.medium,
            border: Border.all(color: kSleekAccent.withOpacity(.42), width: 1.1),
            boxShadow: [BoxShadow(color: kSleekAccent.withOpacity(.10), blurRadius: 16, offset: const Offset(0, 8))],
          ),
          child: Row(
            children: [
              if (current.icon != null) ...[
                Icon(current.icon, size: 22, color: kSleekAccent),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      current.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: textColor,
                            fontWeight: FontWeight.w900,
                          ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Tap to switch to ${next.label}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            color: mutedColor,
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Icon(Icons.swap_horiz_rounded, color: kSleekAccent, size: 24),
            ],
          ),
        ),
      ),
    );
  }
}

class _SleekPillButton<T> extends StatelessWidget {
  const _SleekPillButton({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  final SleekPillOption<T> option;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final selectedColor = kSleekAccent.withOpacity(.32);
    final unselectedColor = Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(.48);
    final borderColor = selected ? kSleekAccent.withOpacity(.42) : Theme.of(context).colorScheme.outline.withOpacity(.24);
    final textColor = selected ? Colors.white : Theme.of(context).colorScheme.onSurface.withOpacity(.76);

    return MotionPressable(
      onTap: onTap,
      borderRadius: AppShapes.medium,
      child: Material(
        color: selected ? selectedColor : unselectedColor,
        borderRadius: AppShapes.medium,
        child: AnimatedContainer(
          duration: AppMotion.fast,
          curve: AppMotion.emphasized,
          constraints: const BoxConstraints(minHeight: 58),
          padding: EdgeInsets.symmetric(horizontal: AppBreakpoints.isSmall(context) ? 8 : 12, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: AppShapes.medium,
            border: Border.all(color: borderColor, width: 1),
            boxShadow: selected
                ? [BoxShadow(color: kSleekAccent.withOpacity(.10), blurRadius: 16, offset: const Offset(0, 8))]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (option.icon != null) ...[
                Icon(option.icon, size: AppBreakpoints.isSmall(context) ? 18 : 20, color: selected ? kSleekAccent : textColor),
                SizedBox(width: AppBreakpoints.isSmall(context) ? 5 : 8),
              ],
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.center,
                  child: Text(
                    option.label,
                    maxLines: 1,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: textColor,
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}


class SelectionOption {
  const SelectionOption({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.iconName,
    required this.iconColor,
  });

  final String id;
  final String title;
  final String subtitle;
  final String iconName;
  final String iconColor;
}

SelectionOption optionFromAccount(Account account, AppController state) => SelectionOption(
      id: account.id,
      title: account.name,
      subtitle: account.type == AccountType.credit
          ? 'Credit • Available ${state.format(account.availableCredit)}'
          : account.type == AccountType.savings
              ? 'Savings account'
              : 'Regular account',
      iconName: account.iconName,
      iconColor: account.iconColor,
    );

SelectionOption optionFromCategory(Category category) => SelectionOption(
      id: category.id,
      title: category.name,
      subtitle: enumName(category.type),
      iconName: category.iconName,
      iconColor: category.iconColor,
    );

class AppleSelectionField extends StatelessWidget {
  const AppleSelectionField({
    super.key,
    required this.label,
    required this.option,
    required this.onTap,
    this.emptyText = 'Select',
  });

  final String label;
  final SelectionOption? option;
  final VoidCallback onTap;
  final String emptyText;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final selected = option;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 6),
          child: Text(
            label,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w800,
                ),
          ),
        ),
        Material(
          color: scheme.surfaceContainerHighest.withOpacity(.52),
          borderRadius: BorderRadius.circular(18),
          child: MotionInkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Theme.of(context).colorScheme.outline.withOpacity(.28), width: .9),
              ),
              child: Row(
                children: [
                  if (selected != null) ...[
                    iconBubble(context, selected.iconName, selected.iconColor, size: 42),
                    const SizedBox(width: 12),
                  ] else ...[
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: kSleekAccent.withOpacity(.13),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: kSleekAccent.withOpacity(.18)),
                      ),
                      child: const Icon(Icons.touch_app_rounded, color: kSleekAccent),
                    ),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          selected?.title ?? emptyText,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          selected?.subtitle ?? 'Tap to choose',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: kSleekMuted, fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(Icons.keyboard_arrow_down_rounded, color: Theme.of(context).colorScheme.onSurfaceVariant),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

const String _selectionAddActionResult = '__koinly_add_selection_option__';

Future<String?> showAppleWheelSelectionSheet(
  BuildContext context, {
  required String title,
  required List<SelectionOption> options,
  required String? selectedId,
  String? addActionLabel,
  Future<String?> Function()? onAdd,
}) async {
  if (options.isEmpty && onAdd == null) return null;
  final foundIndex = options.indexWhere((option) => option.id == selectedId);
  final initialIndex = options.isEmpty ? -1 : (foundIndex < 0 ? 0 : foundIndex);
  var selectedIndex = initialIndex;

  const rowExtent = 72.0;
  final listHeight = options.isEmpty
      ? rowExtent
      : math.min(288.0, math.max(rowExtent, options.length * rowExtent));
  final maxScrollExtent = math.max(0.0, (options.length * rowExtent) - listHeight);
  final initialOffset = options.isEmpty
      ? 0.0
      : math.min(
          maxScrollExtent,
          math.max(0.0, (initialIndex - 1) * rowExtent),
        );
  final listController = ScrollController(initialScrollOffset: initialOffset);
  final hasAddAction = onAdd != null && addActionLabel != null && addActionLabel.trim().isNotEmpty;

  final result = await showKoinlyPopup<String>(
    context,
    maxWidth: 520,
    maxHeight: math.min(680.0, (hasAddAction ? 250.0 : 184.0) + listHeight),
    child: StatefulBuilder(
      builder: (dialogContext, setModalState) {
        final safeIndex = options.isEmpty
            ? -1
            : selectedIndex < 0
                ? 0
                : selectedIndex >= options.length
                    ? options.length - 1
                    : selectedIndex;
        final dark = Theme.of(dialogContext).brightness == Brightness.dark;
        final innerColor = dark ? kSleekSurfaceLow : kSleekLightBackground;
        final innerBorderColor = dark ? kSleekOutlineVariant : kSleekLightOutlineVariant;
        final handleColor = dark ? const Color(0xFF466057) : const Color(0xFFB7C9BF);

        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 44,
                height: 5,
                decoration: BoxDecoration(color: handleColor, borderRadius: BorderRadius.circular(999)),
              ),
              const SizedBox(height: 18),
              Text(
                title,
                textAlign: TextAlign.center,
                style: Theme.of(dialogContext).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 12),
              Container(
                height: listHeight,
                decoration: BoxDecoration(
                  color: innerColor,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: innerBorderColor),
                ),
                clipBehavior: Clip.antiAlias,
                child: options.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: Text(
                            'Nothing here yet. Add one to continue.',
                            textAlign: TextAlign.center,
                            style: Theme.of(dialogContext).textTheme.bodyMedium?.copyWith(
                                  color: Theme.of(dialogContext).colorScheme.onSurfaceVariant,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                        ),
                      )
                    : Scrollbar(
                        controller: listController,
                        thumbVisibility: kIsDesktopApp && options.length > 4,
                        child: ListView.builder(
                          controller: listController,
                          itemExtent: rowExtent,
                          padding: EdgeInsets.zero,
                          physics: optimizedScrollPhysics(dialogContext),
                          itemCount: options.length,
                          itemBuilder: (context, index) {
                            final option = options[index];
                            final isSelected = index == safeIndex;
                            return Material(
                              color: Colors.transparent,
                              child: MotionInkWell(
                                onTap: () => setModalState(() => selectedIndex = index),
                                child: _AppleWheelOptionRow(option: option, selected: isSelected),
                              ),
                            );
                          },
                        ),
                      ),
              ),
              if (hasAddAction) ...[
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => Navigator.pop(dialogContext, _selectionAddActionResult),
                    icon: const Icon(Icons.add_rounded),
                    label: Text(addActionLabel!),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: FilledButton(
                      onPressed: safeIndex < 0 ? null : () => Navigator.pop(dialogContext, options[safeIndex].id),
                      child: const Text('Done'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    ),
  );

  listController.dispose();
  if (result == _selectionAddActionResult && onAdd != null) {
    return onAdd();
  }
  return result;
}

class _AppleWheelOptionRow extends StatelessWidget {
  const _AppleWheelOptionRow({required this.option, required this.selected});

  final SelectionOption option;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final titleStyle = Theme.of(context).textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w900,
          color: selected ? scheme.onSurface : scheme.onSurface.withOpacity(.76),
        );
    final subtitleStyle = Theme.of(context).textTheme.bodySmall?.copyWith(
          color: selected ? kSleekMuted : kSleekMuted.withOpacity(.72),
          fontWeight: FontWeight.w700,
        );

    return AnimatedContainer(
      duration: AppMotion.fast,
      curve: AppMotion.emphasized,
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: selected ? kSleekAccent.withOpacity(.10) : Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: selected ? kSleekAccent.withOpacity(.52) : Colors.transparent,
          width: 1.1,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          iconBubble(context, option.iconName, option.iconColor, size: 42),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(option.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: titleStyle),
                const SizedBox(height: 3),
                Text(option.subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: subtitleStyle),
              ],
            ),
          ),
          if (selected) ...[
            const SizedBox(width: 10),
            const Icon(Icons.check_rounded, color: kSleekAccent, size: 22),
          ],
        ],
      ),
    );
  }
}


Future<DateTime?> pickDate(BuildContext context, DateTime initial) => showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );

class TransactionDateSelection {
  const TransactionDateSelection({
    required this.start,
    required this.end,
    required this.useRange,
  });

  final DateTime start;
  final DateTime end;
  final bool useRange;
}

Future<TransactionDateSelection?> pickTransactionDateSelection(
  BuildContext context,
  DateTime start,
  DateTime end, {
  required bool useRange,
}) {
  final startDate = DateTime(start.year, start.month, start.day);
  final requestedEnd = DateTime(end.year, end.month, end.day);
  final endDate = requestedEnd.isBefore(startDate) ? startDate : requestedEnd;
  return showKoinlyPopup<TransactionDateSelection>(
    context,
    maxWidth: 470,
    maxHeight: 700,
    child: _CenteredDateRangePicker(
      initialRange: DateTimeRange(start: startDate, end: useRange ? endDate : startDate),
      initialUseRange: useRange,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    ),
  );
}

enum _RangeEndpoint { start, end }

class _CenteredDateRangePicker extends StatefulWidget {
  const _CenteredDateRangePicker({
    required this.initialRange,
    required this.initialUseRange,
    required this.firstDate,
    required this.lastDate,
  });

  final DateTimeRange initialRange;
  final bool initialUseRange;
  final DateTime firstDate;
  final DateTime lastDate;

  @override
  State<_CenteredDateRangePicker> createState() => _CenteredDateRangePickerState();
}

class _CenteredDateRangePickerState extends State<_CenteredDateRangePicker> {
  late DateTime _start;
  late DateTime _end;
  late bool _useRange;
  _RangeEndpoint _activeEndpoint = _RangeEndpoint.start;

  @override
  void initState() {
    super.initState();
    _start = widget.initialRange.start;
    _end = widget.initialRange.end;
    _useRange = widget.initialUseRange;
    if (!_useRange) _end = _start;
  }

  DateTime get _activeDate => _activeEndpoint == _RangeEndpoint.start ? _start : _end;

  void _setRangeMode(bool value) {
    if (_useRange == value) return;
    setState(() {
      _useRange = value;
      _activeEndpoint = _RangeEndpoint.start;
      if (_useRange && _end.isBefore(_start)) {
        _end = _start;
      }
    });
  }

  void _selectEndpoint(_RangeEndpoint endpoint) {
    if (!_useRange || _activeEndpoint == endpoint) return;
    setState(() => _activeEndpoint = endpoint);
  }

  void _onDateChanged(DateTime value) {
    final date = DateTime(value.year, value.month, value.day);
    setState(() {
      if (!_useRange) {
        _start = date;
        _activeEndpoint = _RangeEndpoint.start;
        return;
      }

      if (_activeEndpoint == _RangeEndpoint.start) {
        _start = date;
        if (_end.isBefore(_start)) _end = _start;
        _activeEndpoint = _RangeEndpoint.end;
      } else {
        _end = date;
        if (_end.isBefore(_start)) _start = _end;
      }
    });
  }

  void _apply() {
    Navigator.pop(
      context,
      TransactionDateSelection(
        start: _start,
        end: _useRange ? _end : _start,
        useRange: _useRange,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final formatter = DateFormat('MMM d, yyyy');
    final summary = _useRange
        ? '${DateFormat('MMM d').format(_start)} – ${DateFormat('MMM d').format(_end)}'
        : formatter.format(_start);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 4),
          child: Row(
            children: [
              const SizedBox(width: 44),
              Expanded(
                child: Text(
                  _useRange ? 'Select transaction date range' : 'Select transaction date',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
                ),
              ),
              IconButton(
                tooltip: 'Close',
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
        ),
        Expanded(
          child: KoinlyPopupContent(
          padding: const EdgeInsets.fromLTRB(18, 4, 18, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                summary,
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 16),
              SleekPillSelector<bool>(
                options: const [
                  SleekPillOption(value: false, label: 'Single date', icon: Icons.calendar_today_rounded),
                  SleekPillOption(value: true, label: 'Use range', icon: Icons.date_range_rounded),
                ],
                selected: _useRange,
                onChanged: _setRangeMode,
              ),
              const SizedBox(height: 14),
              if (_useRange)
                Row(
                  children: [
                    Expanded(
                      child: _RangeEndpointButton(
                        label: 'Start',
                        value: formatter.format(_start),
                        selected: _activeEndpoint == _RangeEndpoint.start,
                        onTap: () => _selectEndpoint(_RangeEndpoint.start),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _RangeEndpointButton(
                        label: 'End',
                        value: formatter.format(_end),
                        selected: _activeEndpoint == _RangeEndpoint.end,
                        onTap: () => _selectEndpoint(_RangeEndpoint.end),
                      ),
                    ),
                  ],
                )
              else
                _RangeEndpointButton(
                  label: 'Date',
                  value: formatter.format(_start),
                  selected: true,
                  onTap: () {},
                ),
              const SizedBox(height: 10),
              Container(
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest.withOpacity(.34),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: scheme.outline.withOpacity(.18)),
                ),
                child: CalendarDatePicker(
                  key: ValueKey('${_useRange ? _activeEndpoint.name : 'single'}-${_activeDate.millisecondsSinceEpoch}'),
                  initialDate: _activeDate,
                  firstDate: widget.firstDate,
                  lastDate: widget.lastDate,
                  currentDate: DateTime.now(),
                  onDateChanged: _onDateChanged,
                ),
              ),
            ],
          ),
        ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
          decoration: BoxDecoration(
            color: theme.brightness == Brightness.dark ? kSleekSurface : scheme.surface,
            border: Border(top: BorderSide(color: scheme.outline.withOpacity(.12))),
          ),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  onPressed: _apply,
                  child: Text(_useRange ? 'Use range' : 'Use date'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class TransactionTimeSelection {
  const TransactionTimeSelection({
    required this.start,
    required this.end,
    required this.useRange,
  });

  final TimeOfDay start;
  final TimeOfDay end;
  final bool useRange;
}

Future<TransactionTimeSelection?> pickTransactionTimeSelection(
  BuildContext context,
  TimeOfDay start,
  TimeOfDay end, {
  required bool useRange,
  required bool datesSpanMultipleDays,
}) {
  return showKoinlyPopup<TransactionTimeSelection>(
    context,
    maxWidth: 470,
    maxHeight: 560,
    child: _CenteredTimeRangePicker(
      initialStart: start,
      initialEnd: useRange ? end : start,
      initialUseRange: useRange,
      datesSpanMultipleDays: datesSpanMultipleDays,
    ),
  );
}

class _CenteredTimeRangePicker extends StatefulWidget {
  const _CenteredTimeRangePicker({
    required this.initialStart,
    required this.initialEnd,
    required this.initialUseRange,
    required this.datesSpanMultipleDays,
  });

  final TimeOfDay initialStart;
  final TimeOfDay initialEnd;
  final bool initialUseRange;
  final bool datesSpanMultipleDays;

  @override
  State<_CenteredTimeRangePicker> createState() => _CenteredTimeRangePickerState();
}

class _CenteredTimeRangePickerState extends State<_CenteredTimeRangePicker> {
  late TimeOfDay _start;
  late TimeOfDay _end;
  late bool _useRange;
  _RangeEndpoint _activeEndpoint = _RangeEndpoint.start;

  @override
  void initState() {
    super.initState();
    _start = widget.initialStart;
    _end = widget.initialEnd;
    _useRange = widget.initialUseRange;
    if (!_useRange) _end = _start;
  }

  int _minutes(TimeOfDay value) => value.hour * 60 + value.minute;

  void _setRangeMode(bool value) {
    if (_useRange == value) return;
    setState(() {
      _useRange = value;
      _activeEndpoint = _RangeEndpoint.start;
      if (_useRange && !widget.datesSpanMultipleDays && _minutes(_end) <= _minutes(_start)) {
        final proposed = math.min(_minutes(_start) + 60, (24 * 60) - 1);
        _end = TimeOfDay(hour: proposed ~/ 60, minute: proposed % 60);
      }
    });
  }

  Future<void> _pickEndpoint(_RangeEndpoint endpoint) async {
    if (_activeEndpoint != endpoint) setState(() => _activeEndpoint = endpoint);
    final initial = endpoint == _RangeEndpoint.start ? _start : _end;
    final selected = await showTimePicker(context: context, initialTime: initial);
    if (!mounted || selected == null) return;
    setState(() {
      if (endpoint == _RangeEndpoint.start) {
        _start = selected;
        if (_useRange) {
          _activeEndpoint = _RangeEndpoint.end;
        }
      } else {
        _end = selected;
      }
    });
  }

  void _apply() {
    if (_useRange && !widget.datesSpanMultipleDays && _minutes(_end) <= _minutes(_start)) {
      showSnack(context, 'End time must be after start time for a single-day transaction');
      return;
    }
    Navigator.pop(
      context,
      TransactionTimeSelection(
        start: _start,
        end: _useRange ? _end : _start,
        useRange: _useRange,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final localizations = MaterialLocalizations.of(context);
    String format(TimeOfDay value) => localizations.formatTimeOfDay(value);
    final summary = _useRange ? '${format(_start)} – ${format(_end)}' : format(_start);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 4),
          child: Row(
            children: [
              const SizedBox(width: 44),
              Expanded(
                child: Text(
                  _useRange ? 'Select transaction time range' : 'Select transaction time',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
                ),
              ),
              IconButton(
                tooltip: 'Close',
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
        ),
        Expanded(
          child: KoinlyPopupContent(
          padding: const EdgeInsets.fromLTRB(18, 4, 18, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                summary,
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 16),
              SleekPillSelector<bool>(
                options: const [
                  SleekPillOption(value: false, label: 'Single time', icon: Icons.schedule_rounded),
                  SleekPillOption(value: true, label: 'Use range', icon: Icons.timelapse_rounded),
                ],
                selected: _useRange,
                onChanged: _setRangeMode,
              ),
              const SizedBox(height: 16),
              if (_useRange)
                Row(
                  children: [
                    Expanded(
                      child: _RangeEndpointButton(
                        label: 'Start',
                        value: format(_start),
                        selected: _activeEndpoint == _RangeEndpoint.start,
                        onTap: () => _pickEndpoint(_RangeEndpoint.start),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _RangeEndpointButton(
                        label: 'End',
                        value: format(_end),
                        selected: _activeEndpoint == _RangeEndpoint.end,
                        onTap: () => _pickEndpoint(_RangeEndpoint.end),
                      ),
                    ),
                  ],
                )
              else
                _RangeEndpointButton(
                  label: 'Time',
                  value: format(_start),
                  selected: true,
                  onTap: () => _pickEndpoint(_RangeEndpoint.start),
                ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: () => _pickEndpoint(_activeEndpoint),
                icon: const Icon(Icons.schedule_rounded),
                label: Text(_useRange
                    ? 'Change ${_activeEndpoint == _RangeEndpoint.start ? 'start' : 'end'} time'
                    : 'Change time'),
              ),
              const SizedBox(height: 10),
              Text(
                _useRange
                    ? 'Tap Start or End to edit either time. The transaction remains one record and its amount is counted once.'
                    : 'Use range only when this transaction should cover a start and end time.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant, fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
          decoration: BoxDecoration(
            color: theme.brightness == Brightness.dark ? kSleekSurface : scheme.surface,
            border: Border(top: BorderSide(color: scheme.outline.withOpacity(.12))),
          ),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  onPressed: _apply,
                  child: Text(_useRange ? 'Use range' : 'Use time'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _RangeEndpointButton extends StatelessWidget {
  const _RangeEndpointButton({
    required this.label,
    required this.value,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String value;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: selected ? kSleekAccent.withOpacity(.18) : scheme.surfaceContainerHighest.withOpacity(.45),
      borderRadius: BorderRadius.circular(18),
      child: MotionInkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: selected ? kSleekAccent.withOpacity(.72) : scheme.outline.withOpacity(.18)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: Theme.of(context).textTheme.labelMedium?.copyWith(color: selected ? kSleekAccent : scheme.onSurfaceVariant, fontWeight: FontWeight.w900)),
              const SizedBox(height: 2),
              Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w800)),
            ],
          ),
        ),
      ),
    );
  }
}

Future<TimeOfDay?> pickTime(BuildContext context, TimeOfDay initial) => showTimePicker(context: context, initialTime: initial);

OverlayEntry? _activeKoinlySnackEntry;

enum _KoinlySnackKind { success, failure, warning, info }

_KoinlySnackKind _snackKindFor(String message) {
  final lower = message.toLowerCase();
  const failures = ['failed', 'failure', 'error', 'could not', "couldn't", 'malformed', 'unavailable'];
  const successes = ['saved', 'added', 'created', 'updated', 'deleted', 'removed', 'recorded', 'copied', 'recovered', 'connected', 'uploaded', 'complete', 'completed', 'restored', 'merged', 'purchased'];
  const warnings = ['cancelled', 'canceled', 'reset', 'already running', 'overdue'];
  if (failures.any(lower.contains)) return _KoinlySnackKind.failure;
  if (successes.any(lower.contains)) return _KoinlySnackKind.success;
  if (warnings.any(lower.contains)) return _KoinlySnackKind.warning;
  return _KoinlySnackKind.info;
}

void _showRichSnack(BuildContext context, String message, _KoinlySnackKind kind) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (overlay == null) {
    messenger?.hideCurrentSnackBar();
    messenger?.hideCurrentMaterialBanner();
    messenger?.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text(message),
      ),
    );
    return;
  }

  _activeKoinlySnackEntry?.remove();
  _activeKoinlySnackEntry = null;
  messenger?.hideCurrentSnackBar();
  messenger?.hideCurrentMaterialBanner();

  final (title, contentType, color) = switch (kind) {
    _KoinlySnackKind.success => ('Done', ContentType.success, kSleekAccent),
    _KoinlySnackKind.failure => ('Something went wrong', ContentType.failure, kSleekExpense),
    _KoinlySnackKind.warning => ('Please note', ContentType.warning, kSleekWarning),
    _KoinlySnackKind.info => ('Koinly', ContentType.help, kSleekAccent),
  };
  final duration = kind == _KoinlySnackKind.failure
      ? const Duration(seconds: 5)
      : const Duration(milliseconds: 3600);

  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (overlayContext) => _KoinlyTopFeedbackBanner(
      title: title,
      message: message,
      color: color,
      contentType: contentType,
      visibleDuration: duration,
      onDismissed: () {
        if (_activeKoinlySnackEntry == entry) {
          _activeKoinlySnackEntry = null;
          entry.remove();
        }
      },
    ),
  );
  _activeKoinlySnackEntry = entry;
  overlay.insert(entry);
}

class _KoinlyTopFeedbackBanner extends StatefulWidget {
  const _KoinlyTopFeedbackBanner({
    required this.title,
    required this.message,
    required this.color,
    required this.contentType,
    required this.visibleDuration,
    required this.onDismissed,
  });

  final String title;
  final String message;
  final Color color;
  final ContentType contentType;
  final Duration visibleDuration;
  final VoidCallback onDismissed;

  @override
  State<_KoinlyTopFeedbackBanner> createState() => _KoinlyTopFeedbackBannerState();
}

class _KoinlyTopFeedbackBannerState extends State<_KoinlyTopFeedbackBanner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  Timer? _hideTimer;
  bool _closing = false;

  IconData get _icon {
    if (widget.contentType == ContentType.failure) return Icons.error_outline_rounded;
    if (widget.contentType == ContentType.warning) return Icons.warning_amber_rounded;
    if (widget.contentType == ContentType.help) return Icons.info_outline_rounded;
    return Icons.check_rounded;
  }

  String get _semanticType {
    if (widget.contentType == ContentType.failure) return 'Error';
    if (widget.contentType == ContentType.warning) return 'Warning';
    if (widget.contentType == ContentType.help) return 'Information';
    return 'Success';
  }

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
      reverseDuration: const Duration(milliseconds: 180),
    )..forward();
    _hideTimer = Timer(widget.visibleDuration, _dismiss);
  }

  Future<void> _dismiss() async {
    if (_closing || !mounted) return;
    _closing = true;
    _hideTimer?.cancel();
    if (!MediaQuery.of(context).disableAnimations) {
      await _controller.reverse();
    }
    if (mounted) widget.onDismissed();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    final reduceMotion = media.disableAnimations;
    final maxWidth = math.min(kIsDesktopApp ? 500.0 : 520.0, math.max(280.0, media.size.width - 24));
    final topInset = media.padding.top + (kIsDesktopApp ? 14.0 : 10.0);
    final surface = Color.alphaBlend(
      widget.color.withOpacity(dark ? .08 : .055),
      dark ? scheme.surfaceContainerHigh : scheme.surface,
    );

    final card = Semantics(
      liveRegion: true,
      label: '$_semanticType. ${widget.title}. ${widget.message}',
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: maxWidth,
          constraints: const BoxConstraints(minHeight: 68, maxHeight: 94),
          padding: const EdgeInsets.fromLTRB(12, 10, 7, 10),
          decoration: BoxDecoration(
            color: surface.withOpacity(.985),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: widget.color.withOpacity(dark ? .28 : .22)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(dark ? .30 : .14),
                blurRadius: 24,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: widget.color.withOpacity(.14),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: widget.color.withOpacity(.22)),
                ),
                child: Icon(_icon, color: widget.color, size: 21),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: scheme.onSurface,
                        fontWeight: FontWeight.w900,
                        height: 1.05,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      widget.message,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                        height: 1.18,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              SizedBox(
                width: 36,
                height: 36,
                child: IconButton(
                  onPressed: _dismiss,
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Dismiss',
                  icon: Icon(Icons.close_rounded, color: scheme.onSurfaceVariant, size: 20),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    Widget animatedCard = card;
    if (!reduceMotion) {
      final curved = CurvedAnimation(
        parent: _controller,
        curve: AppMotion.emphasized,
        reverseCurve: AppMotion.emphasizedAccelerate,
      );
      animatedCard = FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween<Offset>(begin: const Offset(0, -.18), end: Offset.zero).animate(curved),
          child: ScaleTransition(
            scale: Tween<double>(begin: .985, end: 1).animate(curved),
            child: card,
          ),
        ),
      );
    }

    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
          Positioned(
            top: topInset,
            left: 12,
            right: 12,
            child: Center(child: animatedCard),
          ),
        ],
      ),
    );
  }
}

void showSnack(BuildContext context, String message) {
  final trimmedMessage = message.trim();
  if (trimmedMessage.isEmpty) return;

  final kind = _snackKindFor(trimmedMessage);
  if (kind != _KoinlySnackKind.info && ScaffoldMessenger.maybeOf(context) != null) {
    _showRichSnack(context, trimmedMessage, kind);
    return;
  }

  ScaffoldMessenger.maybeOf(context)?.hideCurrentMaterialBanner();
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) {
    _showRichSnack(context, trimmedMessage, kind);
    return;
  }

  _activeKoinlySnackEntry?.remove();
  _activeKoinlySnackEntry = null;

  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (overlayContext) => _KoinlyDynamicIslandSnack(
      message: trimmedMessage,
      onDismissed: () {
        if (_activeKoinlySnackEntry == entry) {
          _activeKoinlySnackEntry = null;
          entry.remove();
        }
      },
    ),
  );

  _activeKoinlySnackEntry = entry;
  overlay.insert(entry);
}

class _KoinlyDynamicIslandSnack extends StatefulWidget {
  const _KoinlyDynamicIslandSnack({required this.message, required this.onDismissed});

  final String message;
  final VoidCallback onDismissed;

  @override
  State<_KoinlyDynamicIslandSnack> createState() => _KoinlyDynamicIslandSnackState();
}

class _KoinlyDynamicIslandSnackState extends State<_KoinlyDynamicIslandSnack> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  Timer? _hideTimer;

  bool get _isProblemMessage {
    final lower = widget.message.toLowerCase();
    return lower.contains('failed') ||
        lower.contains('error') ||
        lower.contains('invalid') ||
        lower.contains('check') ||
        lower.contains('missing');
  }

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 620),
      reverseDuration: const Duration(milliseconds: 260),
    );
    _controller.forward();
    _hideTimer = Timer(const Duration(milliseconds: 3400), () async {
      if (!mounted) return;
      await _controller.reverse();
      if (mounted) widget.onDismissed();
    });
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final maxWidth = math.min(kIsDesktopApp ? 520.0 : 560.0, math.max(280.0, media.size.width - 28));
    final expandedHeight = widget.message.length > 96 ? 108.0 : widget.message.length > 54 ? 86.0 : 64.0;
    final topInset = media.padding.top + (kIsDesktopApp ? 14.0 : 8.0);

    return IgnorePointer(
      child: Material(
        type: MaterialType.transparency,
        child: Stack(
          children: [
            AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                final raw = _controller.value;
                final t = AppMotion.emphasized.transform(raw);
                final contentT = (((t - .34) / .66).clamp(0.0, 1.0)).toDouble();
                final width = ui.lerpDouble(92, maxWidth, t)!;
                final height = ui.lerpDouble(38, expandedHeight, t)!;
                final radius = ui.lerpDouble(999, 28, t)!;
                final y = ui.lerpDouble(-52, 0, t)!;
                final compactScale = ui.lerpDouble(.72, 1, t)!;
                final borderOpacity = ui.lerpDouble(.16, .09, t)!;
                final icon = _isProblemMessage ? Icons.error_rounded : Icons.check_circle_rounded;
                final iconColor = _isProblemMessage ? kSleekWarning : kSleekAccent;

                return Positioned(
                  top: topInset + y,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Transform.scale(
                      scale: compactScale,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(radius),
                        child: BackdropFilter(
                          filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 80),
                            curve: Curves.linear,
                            width: width,
                            height: height,
                            decoration: BoxDecoration(
                              color: dark ? const Color(0xF20A1518) : const Color(0xF20F172A),
                              borderRadius: BorderRadius.circular(radius),
                              border: Border.all(color: Colors.white.withOpacity(borderOpacity)),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(dark ? .42 : .24),
                                  blurRadius: 34,
                                  offset: const Offset(0, 16),
                                ),
                              ],
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(radius),
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  Align(
                                    alignment: Alignment.center,
                                    child: Container(
                                      width: ui.lerpDouble(34, 0, contentT)!,
                                      height: ui.lerpDouble(6, 0, contentT)!,
                                      decoration: BoxDecoration(
                                        color: Colors.white.withOpacity(ui.lerpDouble(.72, 0, contentT)!),
                                        borderRadius: AppShapes.full,
                                      ),
                                    ),
                                  ),
                                  Opacity(
                                    opacity: contentT,
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 14),
                                      child: Row(
                                        children: [
                                          Container(
                                            width: 38,
                                            height: 38,
                                            decoration: BoxDecoration(
                                              color: iconColor.withOpacity(.18),
                                              borderRadius: BorderRadius.circular(18),
                                              border: Border.all(color: iconColor.withOpacity(.22)),
                                            ),
                                            child: Icon(icon, color: iconColor, size: 21),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Text(
                                              widget.message,
                                              maxLines: 3,
                                              overflow: TextOverflow.ellipsis,
                                              style: theme.textTheme.bodyMedium?.copyWith(
                                                color: Colors.white,
                                                fontWeight: FontWeight.w900,
                                                height: 1.14,
                                                letterSpacing: -.1,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}


Future<T?> showKoinlyPopup<T>(
  BuildContext context, {
  required Widget child,
  double maxWidth = 560,
  double maxHeight = 760,
  bool barrierDismissible = true,
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.black.withOpacity(.62),
    transitionDuration: AppMotion.medium,
    pageBuilder: (dialogContext, animation, secondaryAnimation) {
      return _KoinlyPopupFrame(maxWidth: maxWidth, maxHeight: maxHeight, child: child);
    },
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      if (MediaQuery.of(context).disableAnimations) return child;
      final fade = CurvedAnimation(
        parent: animation,
        curve: AppMotion.standard,
        reverseCurve: AppMotion.emphasizedAccelerate,
      );
      final motion = CurvedAnimation(
        parent: animation,
        curve: AppMotion.spring,
        reverseCurve: AppMotion.emphasizedAccelerate,
      );
      return FadeTransition(
        opacity: fade,
        child: ScaleTransition(
          scale: Tween<double>(begin: .955, end: 1).animate(motion),
          child: SlideTransition(
            position: Tween<Offset>(begin: const Offset(0, .025), end: Offset.zero).animate(motion),
            child: child,
          ),
        ),
      );
    },
  );
}

class _KoinlyPopupFrame extends StatelessWidget {
  const _KoinlyPopupFrame({required this.child, required this.maxWidth, required this.maxHeight});

  final Widget child;
  final double maxWidth;
  final double maxHeight;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final horizontalInset = media.size.width < 420 ? 12.0 : 20.0;
    final verticalInset = media.size.height < 720 ? 10.0 : 20.0;
    final availableWidth = math.max(280.0, media.size.width - (horizontalInset * 2));
    final availableHeight = math.max(
      300.0,
      media.size.height - media.padding.top - media.padding.bottom - media.viewInsets.bottom - (verticalInset * 2),
    );
    final resolvedWidth = math.min(maxWidth, availableWidth);
    final resolvedHeight = math.min(maxHeight, availableHeight);

    return _KeyboardDismissOnBack(
      child: Material(
        type: MaterialType.transparency,
        child: SafeArea(
          child: AnimatedPadding(
            duration: AppMotion.fast,
            curve: AppMotion.emphasized,
            padding: EdgeInsets.fromLTRB(horizontalInset, verticalInset, horizontalInset, verticalInset + media.viewInsets.bottom),
            child: Align(
              alignment: Alignment.center,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: resolvedWidth, maxHeight: resolvedHeight),
                child: Material(
                  color: dark ? kSleekSurface : scheme.surface,
                  elevation: 18,
                  shadowColor: Colors.black.withOpacity(.45),
                  borderRadius: BorderRadius.circular(media.size.width < 420 ? 30 : 34),
                  clipBehavior: Clip.antiAlias,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(media.size.width < 420 ? 30 : 34),
                      border: Border.all(color: dark ? Colors.white.withOpacity(.08) : scheme.outline.withOpacity(.16)),
                    ),
                    child: child,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}


/// Fixed-size popup body used by center dialogs.
///
/// Center popups intentionally do not become full-card scroll views. The body
/// keeps its natural size and, only when the available viewport is shorter
/// than the content (for example on a small phone or while the keyboard is
/// open), scales down as one unit so every action remains visible.
class KoinlyPopupContent extends StatelessWidget {
  const KoinlyPopupContent({
    super.key,
    required this.child,
    this.padding = EdgeInsets.zero,
    this.alignment = Alignment.topCenter,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final AlignmentGeometry alignment;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final resolvedPadding = padding.resolve(Directionality.of(context));
        final availableWidth = constraints.maxWidth.isFinite
            ? math.max(1.0, constraints.maxWidth - resolvedPadding.horizontal)
            : 560.0;
        final body = SizedBox(width: availableWidth, child: child);
        if (!constraints.maxHeight.isFinite) {
          return Padding(padding: resolvedPadding, child: body);
        }
        return Padding(
          padding: resolvedPadding,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: alignment,
            child: body,
          ),
        );
      },
    );
  }
}

// -----------------------------------------------------------------------------
// Onboarding
// -----------------------------------------------------------------------------

enum InitialSetupChoice { restoreBackup, startNew }

Future<InitialSetupChoice?> showInitialSetupChoice(
  BuildContext context, {
  required bool syncAccountCreated,
}) {
  return showKoinlyPopup<InitialSetupChoice>(
    context,
    maxWidth: 560,
    maxHeight: 620,
    child: _InitialSetupChoicePopup(syncAccountCreated: syncAccountCreated),
  );
}

class _InitialSetupChoicePopup extends StatelessWidget {
  const _InitialSetupChoicePopup({required this.syncAccountCreated});

  final bool syncAccountCreated;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurface.withOpacity(.66);

    Widget choice({
      required IconData icon,
      required String title,
      required String subtitle,
      required InitialSetupChoice value,
      required bool primary,
    }) {
      return Semantics(
        button: true,
        label: '$title. $subtitle',
        child: MotionInkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: () => Navigator.pop(context, value),
          child: Ink(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: primary
                  ? theme.colorScheme.primary.withOpacity(theme.brightness == Brightness.dark ? .14 : .08)
                  : theme.colorScheme.surfaceContainerHighest.withOpacity(theme.brightness == Brightness.dark ? .46 : .72),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: primary
                    ? theme.colorScheme.primary.withOpacity(.55)
                    : theme.colorScheme.outlineVariant.withOpacity(.72),
                width: primary ? 1.4 : 1,
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: primary
                        ? theme.colorScheme.primary.withOpacity(.16)
                        : theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(17),
                  ),
                  child: Icon(icon, color: primary ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
                      const SizedBox(height: 5),
                      Text(subtitle, style: theme.textTheme.bodyMedium?.copyWith(color: muted, fontWeight: FontWeight.w600, height: 1.28)),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Padding(
                  padding: const EdgeInsets.only(top: 11),
                  child: Icon(Icons.chevron_right_rounded, color: muted),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return KoinlyPopupContent(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Set up this device',
                  style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
                ),
              ),
              IconButton(
                tooltip: 'Close',
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            syncAccountCreated
                ? 'Your sync account is ready. Restore an existing Koinly backup or start with a clean setup on this device.'
                : 'Restore an existing Koinly backup or start with a clean local setup.',
            style: theme.textTheme.bodyMedium?.copyWith(color: muted, height: 1.35, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 20),
          choice(
            icon: Icons.restore_rounded,
            title: 'Restore backup',
            subtitle: syncAccountCreated
                ? 'Choose a .koinlybackup file. Its finance data will be merged with this device and then merged into your new sync account.'
                : 'Choose a .koinlybackup file and restore your accounts, categories, transactions, budgets, loans, and preferences.',
            value: InitialSetupChoice.restoreBackup,
            primary: true,
          ),
          const SizedBox(height: 12),
          choice(
            icon: Icons.add_circle_outline_rounded,
            title: 'Start new',
            subtitle: syncAccountCreated
                ? 'Continue with currency and account setup. New data will sync to the account you just created.'
                : 'Continue with currency and account setup and create a new local finance profile.',
            value: InitialSetupChoice.startNew,
            primary: false,
          ),
          const SizedBox(height: 16),
          Text(
            'Restoring a backup merges accounts, categories, transactions, budgets, loans, and preferences with the data already on this device. Matching category names are deduplicated.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(color: muted, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final controller = PageController();
  int index = 0;
  bool choosingInitialSetup = false;

  Future<bool> _restoreInitialBackup({required bool uploadToSyncAccount}) async {
    final state = context.read<AppController>();
    try {
      final restored = await BackupService.restoreBackup(
        state,
        safetyReason: 'Before first-run backup restore',
      );
      if (!restored) return false;

      if (uploadToSyncAccount && state.cloudSyncEnabled) {
        await state.resolveNewSyncAccountWithRestoredData();
      }
      await state.completeOnboarding();
      if (mounted) {
        showSnack(
          context,
          uploadToSyncAccount && state.cloudSyncEnabled
              ? 'Backup restored. Restored data is now the source for this sync account.'
              : 'Backup restored. Setup is complete.',
        );
      }
      return true;
    } on FormatException catch (error) {
      if (mounted) showSnack(context, error.message);
    } catch (_) {
      if (mounted) showSnack(context, 'Could not restore this backup. Please choose a valid Koinly backup file.');
    }
    return false;
  }

  Future<void> _chooseInitialSetup({required bool syncAccountCreated}) async {
    if (choosingInitialSetup) return;
    setState(() => choosingInitialSetup = true);
    try {
      final choice = await showInitialSetupChoice(context, syncAccountCreated: syncAccountCreated);
      if (!mounted || choice == null) return;

      if (choice == InitialSetupChoice.startNew) {
        final state = context.read<AppController>();
        await state.prepareStartNewSetup();
        if (!mounted) return;
        if (syncAccountCreated) {
          await state.resolveNewSyncAccountWithLocalSetup();
          if (!mounted) return;
        }
        await controller.animateToPage(1, duration: AppMotion.medium, curve: Curves.easeOutCubic);
        return;
      }

      await _restoreInitialBackup(uploadToSyncAccount: syncAccountCreated);
    } finally {
      if (mounted) setState(() => choosingInitialSetup = false);
    }
  }

  Future<void> _openAccountSync({required bool createAccount}) async {
    final createdAccount = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => MultiDeviceSyncScreen(
          completeOnAuth: !createAccount,
          returnOnAuth: createAccount,
          initialRegisterMode: createAccount,
          preferCloudDataOnAuth: !createAccount,
        ),
      ),
    );
    if (!mounted || createdAccount != true) return;

    // Registration does not assume whether this device should start clean or
    // restore an existing local backup. Ask immediately after account creation.
    // This also covers users who entered through Login and then switched to
    // "Create account instead" inside the auth screen.
    await _chooseInitialSetup(syncAccountCreated: true);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppController>();
    final signedInSetupPending = !state.onboardingCompleted && state.cloudSyncEnabled && state.syncAccountUsername.trim().isNotEmpty;
    return _KeyboardDismissOnBack(
      child: Scaffold(
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final desktop = constraints.maxWidth >= 900;
              final horizontalPadding = desktop ? 32.0 : 20.0;
              return Column(
                children: [
                  Expanded(
                    child: PageView(
                      controller: controller,
                      physics: const PageScrollPhysics(parent: ClampingScrollPhysics()),
                      onPageChanged: (value) => setState(() => index = value),
                      children: [
                        _OnboardingPane(
                          icon: Icons.account_balance_wallet_rounded,
                          title: 'Track money without losing detail',
                          body: 'Accounts, categories, transactions, budgets, analysis, exports, reminders, and local backup are available from the first setup.',
                          actions: Wrap(
                            alignment: WrapAlignment.center,
                            spacing: 12,
                            runSpacing: 12,
                            children: [
                              if (signedInSetupPending)
                                FilledButton.icon(
                                  onPressed: choosingInitialSetup ? null : () => _chooseInitialSetup(syncAccountCreated: true),
                                  icon: const Icon(Icons.arrow_forward_rounded),
                                  label: const Text('Continue setup'),
                                )
                              else ...[
                                FilledButton.icon(
                                  onPressed: () => _openAccountSync(createAccount: false),
                                  icon: const Icon(Icons.login_rounded),
                                  label: const Text('Login'),
                                ),
                                OutlinedButton.icon(
                                  onPressed: () => _openAccountSync(createAccount: true),
                                  icon: const Icon(Icons.person_add_alt_rounded),
                                  label: const Text('Create account'),
                                ),
                                TextButton.icon(
                                  onPressed: choosingInitialSetup ? null : () => _chooseInitialSetup(syncAccountCreated: false),
                                  icon: const Icon(Icons.wifi_off_rounded),
                                  label: const Text('Use offline'),
                                ),
                              ],
                            ],
                          ),
                        ),
                        CurrencySetupPane(state: state),
                        AccountSetupPane(
                          state: state,
                          onSkip: () async {
                            await state.skipStarterAccounts();
                            if (!mounted) return;
                            await controller.nextPage(duration: AppMotion.medium, curve: Curves.easeOutCubic);
                          },
                        ),
                        _OnboardingPane(
                          icon: Icons.privacy_tip_rounded,
                          title: 'Private local database',
                          body: 'Your main finance data is stored locally with SQLite. Backup and restore stay on this device unless you share a backup file yourself.',
                        ),
                      ],
                    ),
                  ),
                  Container(
                    width: double.infinity,
                    padding: EdgeInsets.fromLTRB(horizontalPadding, 16, horizontalPadding, 20),
                    decoration: BoxDecoration(
                      color: Theme.of(context).scaffoldBackgroundColor.withOpacity(.94),
                      border: Border(top: BorderSide(color: Theme.of(context).colorScheme.outlineVariant.withOpacity(.55))),
                    ),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 780),
                        child: Row(
                          children: [
                            Row(
                              children: List.generate(4, (i) => AnimatedContainer(
                                    duration: AppMotion.medium,
                                    width: i == index ? 24 : 8,
                                    height: 8,
                                    margin: const EdgeInsets.only(right: 6),
                                    decoration: BoxDecoration(borderRadius: BorderRadius.circular(99), color: i == index ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.outlineVariant),
                                  )),
                            ),
                            const Spacer(),
                            if (index > 0)
                              Padding(
                                padding: const EdgeInsets.only(right: 10),
                                child: OutlinedButton(
                                  onPressed: () => controller.previousPage(duration: AppMotion.medium, curve: Curves.easeOutCubic),
                                  child: const Text('Back'),
                                ),
                              ),
                            FilledButton(
                              onPressed: choosingInitialSetup
                                  ? null
                                  : () async {
                                if (index == 0) {
                                  await _chooseInitialSetup(syncAccountCreated: signedInSetupPending);
                                  return;
                                }
                                if (index < 3) {
                                  await controller.nextPage(duration: AppMotion.medium, curve: Curves.easeOutCubic);
                                } else {
                                  await state.completeOnboarding();
                                }
                              },
                              child: Text(index == 0 && signedInSetupPending ? 'Continue' : index < 3 ? 'Next' : 'Start'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

}

class OnboardingPageFrame extends StatelessWidget {
  const OnboardingPageFrame({super.key, required this.child, this.maxWidth = 760});

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final desktop = constraints.maxWidth >= 900;
        final horizontalPadding = desktop ? 40.0 : 24.0;
        final verticalPadding = desktop ? 32.0 : 24.0;
        return SingleChildScrollView(
          physics: optimizedScrollPhysics(context),
          padding: EdgeInsets.symmetric(horizontal: horizontalPadding, vertical: verticalPadding),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: math.max(0, constraints.maxHeight - verticalPadding * 2)),
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxWidth),
                child: child,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _OnboardingPane extends StatelessWidget {
  const _OnboardingPane({required this.icon, required this.title, required this.body, this.actions});
  final IconData icon;
  final String title;
  final String body;
  final Widget? actions;

  @override
  Widget build(BuildContext context) {
    return OnboardingPageFrame(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const KoinlyAppIcon(size: 112),
          const SizedBox(height: 28),
          _AnimatedOnboardingGlyph(icon: icon),
          const SizedBox(height: 16),
          Text(title, textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w900)),
          const SizedBox(height: 16),
          Text(body, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyLarge),
          if (actions != null) ...[
            const SizedBox(height: 24),
            actions!,
          ],
        ],
      ),
    );
  }
}

class _AnimatedOnboardingGlyph extends StatefulWidget {
  const _AnimatedOnboardingGlyph({required this.icon});

  final IconData icon;

  @override
  State<_AnimatedOnboardingGlyph> createState() => _AnimatedOnboardingGlyphState();
}

class _AnimatedOnboardingGlyphState extends State<_AnimatedOnboardingGlyph>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.of(context).disableAnimations) {
      _controller
        ..stop()
        ..value = 0;
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    final reduceMotion = MediaQuery.of(context).disableAnimations;

    Widget buildIcon(double glowStrength) => Icon(
          widget.icon,
          size: 34,
          color: color,
          shadows: [
            Shadow(
              color: color.withOpacity(glowStrength),
              blurRadius: 16,
            ),
          ],
        );

    if (reduceMotion) {
      return SizedBox(
        width: 48,
        height: 48,
        child: Center(child: buildIcon(.18)),
      );
    }

    return SizedBox(
      width: 48,
      height: 48,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          final phase = _controller.value * math.pi * 2;
          final lift = math.sin(phase) * -3.2;
          final turn = math.sin(phase + .7) * .025;
          final scale = 1 + (math.sin(phase + math.pi / 2) * .035);
          final glow = .18 + ((math.sin(phase) + 1) * .07);

          return Transform.translate(
            offset: Offset(0, lift),
            child: Transform.rotate(
              angle: turn,
              child: Transform.scale(
                scale: scale,
                child: Center(child: buildIcon(glow)),
              ),
            ),
          );
        },
      ),
    );
  }
}

class CurrencySetupPane extends StatelessWidget {
  const CurrencySetupPane({super.key, required this.state});
  final AppController state;

  @override
  Widget build(BuildContext context) {
    return OnboardingPageFrame(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const KoinlyAppIcon(size: 82),
          const SizedBox(height: 24),
          Text('Currency setup', style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w900)),
          const SizedBox(height: 12),
          const Text('Choose how every amount is formatted across accounts, budgets, analysis, and exports.', textAlign: TextAlign.center),
          const SizedBox(height: 24),
          CurrencyForm(initialSymbol: state.currencySymbol, initialCode: state.currencyCode, initialPosition: state.currencyPosition, initialSeparators: state.useSeparators),
        ],
      ),
    );
  }
}

class AccountSetupPane extends StatelessWidget {
  const AccountSetupPane({super.key, required this.state, required this.onSkip});
  final AppController state;
  final Future<void> Function() onSkip;

  @override
  Widget build(BuildContext context) {
    return OnboardingPageFrame(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const KoinlyAppIcon(size: 82),
          const SizedBox(height: 24),
          Text('Set up your accounts', style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w900)),
          const SizedBox(height: 12),
          const Text('Keep the starter accounts, add your own, or remove any account you do not need. Tap an account to edit or delete it.', textAlign: TextAlign.center),
          const SizedBox(height: 24),
          ...state.accounts.map((a) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: AccountTile(account: a, onTap: () => showAccountEditor(context, account: a)),
              )),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 12,
            runSpacing: 12,
            children: [
              OutlinedButton.icon(
                onPressed: () => showAccountEditor(context, allowedTypes: AccountType.values),
                icon: const Icon(Icons.add_rounded),
                label: const Text('Add account'),
              ),
              TextButton.icon(
                onPressed: onSkip,
                icon: const Icon(Icons.skip_next_rounded),
                label: const Text('Skip accounts'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Home Dashboard
// -----------------------------------------------------------------------------

class HomeDashboardScreen extends StatelessWidget {
  const HomeDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppController>();
    final range = state.activeRange();
    final txs = state.filteredTransactions();
    final summary = state.summaryFor(txs);
    final accountBalance = state.totalAccountBalance;
    final categoryTotals = state.categoryTotals(CategoryType.expense, source: txs);
    final topCategories = categoryTotals.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final categoryGrandTotal = categoryTotals.values.fold<double>(0, (sum, value) => sum + value);

    final balanceCard = BalanceHeroCard(
      balance: state.format(accountBalance),
      income: state.format(summary.income),
      expense: state.format(summary.expense),
      subtitle: '${state.accounts.length} accounts total • ${range.label} balance ${state.format(summary.balance)}',
      amountsHidden: state.amountsHidden,
      onToggleAmounts: state.toggleAmountsHidden,
    );

    final accountsSection = <Widget>[
      const SectionHeader('Accounts'),
      HomeNavigationTile(
        iconName: 'wallet',
        iconColor: kSleekAccentHex,
        title: 'Accounts',
        subtitle: '${state.operatingAccounts.length} regular accounts',
        amount: state.format(state.operatingAccountBalance),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AccountListScreen())),
      ),
      const SizedBox(height: 10),
      HomeNavigationTile(
        iconName: 'savings',
        iconColor: '#A6E3A1',
        title: 'Savings Accounts',
        subtitle: state.savingAccounts.length == 1 ? '1 savings account' : '${state.savingAccounts.length} savings accounts',
        amount: state.format(state.savingAccountBalance),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AccountListScreen(filterType: AccountType.savings, title: 'Savings Accounts'))),
      ),
    ];

    final budgetSection = <Widget>[
      SectionHeader('Budgets', trailing: TextButton(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const BudgetListScreen())), child: const Text('View all'))),
      if (state.budgets.isEmpty)
        EmptyCard(icon: Icons.savings_rounded, title: 'No budget yet', body: 'Create a monthly budget and track spending against limits.', action: () => showBudgetEditor(context), actionLabel: 'Create budget', animated: true)
      else
        ...state.budgetProgress().take(2).map((b) => Padding(padding: const EdgeInsets.only(bottom: 10), child: BudgetProgressTile(progress: b))),
    ];



    final categorySection = <Widget>[
      SectionHeader('Category spending'),
      if (topCategories.isEmpty)
        const EmptyCard(icon: Icons.pie_chart_rounded, title: 'No spending data', body: 'Add expenses to see where money is going.', animated: true)
      else
        ExpressiveCard(
          child: Column(
            children: topCategories.take(4).map((entry) {
              final category = state.categoryOf(entry.key);
              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: category == null ? null : iconBubble(context, category.iconName, category.iconColor),
                title: Text(category?.name ?? 'Unknown'),
                subtitle: LinearProgressIndicator(value: categoryGrandTotal <= 0 ? 0 : entry.value / categoryGrandTotal),
                trailing: Text(state.format(entry.value), style: const TextStyle(fontWeight: FontWeight.w800)),
                onTap: category == null ? null : () => Navigator.push(context, MaterialPageRoute(builder: (_) => CategoryTransactionScreen(category: category))),
              );
            }).toList(),
          ),
        ),
    ];

    final startEmptySection = <Widget>[
      if (state.accounts.isEmpty) ...[
        const SectionHeader('Start from empty'),
        ExpressiveCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  iconBubble(context, 'wallet', kSleekAccentHex, size: 50),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('No accounts yet', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
                        const SizedBox(height: 4),
                        Text('Add an account, merge a backup, or sign in to merge this device with your cloud data.', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: kSleekMuted, fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  FilledButton.icon(
                    onPressed: () => showAccountEditor(context, allowedTypes: const [AccountType.regular, AccountType.credit]),
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Add account'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => runRestoreFlow(context, state),
                    icon: const Icon(Icons.restore_rounded),
                    label: const Text('Restore backup'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MultiDeviceSyncScreen(preferCloudDataOnAuth: true))),
                    icon: const Icon(Icons.cloud_download_rounded),
                    label: const Text('Sign in & restore cloud'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    ];


    return PageScaffold(
      title: 'Home',
      subtitle: range.label,
      actions: [
        IconButton(onPressed: () => showDateRangeSheet(context), icon: const Icon(Icons.date_range_rounded)),
        IconButton(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen())), icon: const Icon(Icons.settings_rounded)),
      ],
      child: ResponsiveContent(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final useDesktopColumns = constraints.maxWidth >= 860;
            if (!useDesktopColumns) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  balanceCard,
                  ...startEmptySection,
                  ...accountsSection,
                  ...budgetSection,
                  ...categorySection,
                ],
              );
            }

            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 5,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      balanceCard,
                      ...startEmptySection,
                      ...accountsSection,
                      ...budgetSection,
                    ],
                  ),
                ),
                const SizedBox(width: 18),
                Expanded(
                  flex: 4,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ...categorySection,
                        ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}


class HomeNavigationTile extends StatelessWidget {
  const HomeNavigationTile({
    super.key,
    required this.iconName,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.amount,
    required this.onTap,
  });

  final String iconName;
  final String iconColor;
  final String title;
  final String subtitle;
  final String amount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return MotionTouchFeedback(
      enabled: true,
      scale: .985,
      child: ExpressiveCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        leading: iconBubble(context, iconName, iconColor, size: 50),
        title: Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
        subtitle: Text(
          subtitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: kSleekMuted, fontWeight: FontWeight.w700),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(amount, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900)),
            const SizedBox(width: 6),
            Icon(Icons.chevron_right_rounded, color: Theme.of(context).colorScheme.onSurfaceVariant),
          ],
        ),
        onTap: onTap,
      ),
    ),
    );
  }
}

class QuickActionTile extends StatelessWidget {
  const QuickActionTile({
    super.key,
    required this.iconName,
    required this.iconColor,
    required this.label,
    required this.onTap,
  });

  final String iconName;
  final String iconColor;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final accent = colorFromHex(iconColor, fallback: kSleekAccent);
    return Semantics(
      button: true,
      label: label.replaceAll('\n', ' '),
      child: MotionInkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: AnimatedContainer(
          duration: AppMotion.fast,
          curve: AppMotion.spring,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          decoration: BoxDecoration(
            color: dark ? kSleekSurface.withOpacity(.82) : Colors.white.withOpacity(.94),
            gradient: dark
                ? LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color.alphaBlend(accent.withOpacity(.09), kSleekSurface),
                      kSleekSurfaceLow,
                    ],
                  )
                : null,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: dark ? Colors.white.withOpacity(.07) : scheme.outlineVariant.withOpacity(.72)),
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(dark ? .20 : .06), blurRadius: 16, offset: const Offset(0, 8)),
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              iconBubble(context, iconName, iconColor, size: 42),
              const SizedBox(height: 8),
              Text(
                label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: dark ? const Color(0xFFDCE9E2) : scheme.onSurface,
                      fontWeight: FontWeight.w900,
                      height: 1.05,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class MiniMetric extends StatelessWidget {
  const MiniMetric(this.label, this.value, this.icon, {super.key});
  final String label;
  final String value;
  final IconData icon;

  Color _accent() {
    final lower = label.toLowerCase();
    if (lower.contains('income') || lower.contains('saving')) return kSleekIncome;
    if (lower.contains('expense') || lower.contains('spent') || lower.contains('overdue')) return kSleekExpense;
    if (lower.contains('balance') || lower.contains('remaining')) return kSleekAccent;
    if (lower.contains('open')) return const Color(0xFF8AB4FF);
    if (lower.contains('completed')) return const Color(0xFF2BD9A1);
    return kSleekAccent;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final accent = _accent();

    Widget fitted(String text, TextStyle? style, {Alignment alignment = Alignment.centerLeft, TextAlign textAlign = TextAlign.left}) => FittedBox(
          fit: BoxFit.scaleDown,
          alignment: alignment,
          child: Text(
            text,
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.visible,
            textAlign: textAlign,
            style: style,
          ),
        );

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 230;
        return Container(
          constraints: BoxConstraints(minHeight: compact ? 82 : 66),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest.withOpacity(Theme.of(context).brightness == Brightness.dark ? .42 : .48),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: colorScheme.outline.withOpacity(.24), width: .8),
            boxShadow: Theme.of(context).brightness == Brightness.dark ? [BoxShadow(color: Colors.black.withOpacity(.12), blurRadius: 14, offset: const Offset(0, 8))] : null,
          ),
          child: compact
              ? Row(
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(color: accent.withOpacity(.14), borderRadius: BorderRadius.circular(12)),
                      child: Icon(icon, color: accent, size: 21),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(width: double.infinity, child: fitted(label, textTheme.labelMedium?.copyWith(color: colorScheme.onSurfaceVariant, fontWeight: FontWeight.w800))),
                          const SizedBox(height: 5),
                          SizedBox(width: double.infinity, child: fitted(value, textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900, color: colorScheme.onSurface))),
                        ],
                      ),
                    ),
                  ],
                )
              : Row(
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(color: accent.withOpacity(.14), borderRadius: BorderRadius.circular(12)),
                      child: Icon(icon, color: accent, size: 21),
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: fitted(label, textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant, fontWeight: FontWeight.w700))),
                    const SizedBox(width: 12),
                    Flexible(child: fitted(value, textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900), alignment: Alignment.centerRight, textAlign: TextAlign.right)),
                  ],
                ),
        );
      },
    );
  }
}

class BalanceHeroCard extends StatelessWidget {
  const BalanceHeroCard({
    super.key,
    required this.balance,
    required this.income,
    required this.expense,
    required this.subtitle,
    required this.amountsHidden,
    required this.onToggleAmounts,
  });
  final String balance;
  final String income;
  final String expense;
  final String subtitle;
  final bool amountsHidden;
  final VoidCallback onToggleAmounts;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final titleColor = dark ? const Color(0xFFD1E8DC) : scheme.onSurface.withOpacity(.86);
    final valueColor = dark ? Colors.white : scheme.onSurface;
    final subtitleColor = dark ? const Color(0xFF96ACA2) : scheme.onSurfaceVariant.withOpacity(.78);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: dark
            ? LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  const Color(0xFF0A3A28),
                  const Color(0xFF0B281D),
                  kSleekSurface,
                ],
              )
            : LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.white,
                  const Color(0xFFF1FAF5),
                  scheme.surface,
                ],
              ),
        border: Border.all(color: dark ? kSleekAccent.withOpacity(.28) : scheme.outline.withOpacity(.16), width: 1),
        boxShadow: kIsDesktopApp
            ? [
                BoxShadow(color: Colors.black.withOpacity(dark ? .24 : .055), blurRadius: 28, offset: const Offset(0, 14)),
                if (dark) BoxShadow(color: kSleekAccent.withOpacity(.10), blurRadius: 36, offset: const Offset(0, 5)),
              ]
            : [
                BoxShadow(color: kSleekAccent.withOpacity(dark ? .13 : .05), blurRadius: 24, offset: const Offset(0, 9)),
                BoxShadow(color: Colors.black.withOpacity(dark ? .32 : .055), blurRadius: 20, offset: const Offset(0, 10)),
              ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Net Balance', style: Theme.of(context).textTheme.labelLarge?.copyWith(color: titleColor, fontWeight: FontWeight.w800)),
              const SizedBox(width: 6),
              Tooltip(
                message: amountsHidden ? 'Show amounts' : 'Hide amounts',
                child: MotionInkWell(
                  borderRadius: BorderRadius.circular(999),
                  onTap: onToggleAmounts,
                  child: Padding(
                    padding: const EdgeInsets.all(3),
                    child: Icon(
                      amountsHidden ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                      size: 16,
                      color: dark ? const Color(0xFF93DFBC) : kSleekAccent.withOpacity(.82),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(balance, maxLines: 1, softWrap: false, style: Theme.of(context).textTheme.displaySmall?.copyWith(fontWeight: FontWeight.w900, letterSpacing: -1.2, color: valueColor)),
            ),
          ),
          const SizedBox(height: 8),
          Text(subtitle, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: subtitleColor, fontWeight: FontWeight.w800)),
          const SizedBox(height: 16),
          const _DecorativeSparkline(),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(child: MiniMetric('Total income', income, Icons.south_west_rounded)),
              const SizedBox(width: 10),
              Expanded(child: MiniMetric('Total expense', expense, Icons.north_east_rounded)),
            ],
          ),
        ],
      ),
    );
  }
}

class _DecorativeSparkline extends StatefulWidget {
  const _DecorativeSparkline();

  @override
  State<_DecorativeSparkline> createState() => _DecorativeSparklineState();
}

class _DecorativeSparklineState extends State<_DecorativeSparkline> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  static const _baseValues = <double>[1.2, 1.7, 1.4, 2.4, 2.1, 3.2, 2.9, 4.0];

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 3600));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.of(context).disableAnimations) {
      _controller
        ..stop()
        ..value = 0;
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  List<FlSpot> _spots(double animationValue) {
    final phase = animationValue * math.pi * 2;
    return List<FlSpot>.generate(_baseValues.length, (index) {
      final bob = math.sin(phase + index * .9) * .12;
      final secondary = math.sin(phase * .55 + index * .48) * .045;
      return FlSpot(index.toDouble(), _baseValues[index] + bob + secondary);
    });
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    return RepaintBoundary(
      child: SizedBox(
        height: 54,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            final animationValue = reduceMotion ? 0.0 : _controller.value;
            final glow = .20 + math.sin(animationValue * math.pi * 2) * .04;
            return LineChart(
              LineChartData(
                minX: 0,
                maxX: 7,
                minY: 0,
                maxY: 4.5,
                gridData: const FlGridData(show: false),
                borderData: FlBorderData(show: false),
                titlesData: const FlTitlesData(show: false),
                lineTouchData: const LineTouchData(enabled: false),
                lineBarsData: [
                  LineChartBarData(
                    spots: _spots(animationValue),
                    isCurved: true,
                    preventCurveOverShooting: true,
                    color: kSleekAccent,
                    barWidth: 3,
                    dotData: const FlDotData(show: false),
                    belowBarData: BarAreaData(
                      show: true,
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [kSleekAccent.withOpacity(glow), kSleekAccent.withOpacity(0)],
                      ),
                    ),
                  ),
                ],
              ),
              duration: Duration.zero,
            );
          },
        ),
      ),
    );
  }
}

class KoinlyInlineLoader extends StatelessWidget {
  const KoinlyInlineLoader({super.key, this.size = 18, this.color});

  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return SpinKitThreeBounce(
      color: color ?? Theme.of(context).colorScheme.primary,
      size: size,
    );
  }
}

class KoinlyPageLoader extends StatelessWidget {
  const KoinlyPageLoader({super.key, this.size = 38});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SpinKitFadingCircle(
        color: Theme.of(context).colorScheme.primary,
        size: size,
      ),
    );
  }
}

class _AnimatedEmptyStateIcon extends StatefulWidget {
  const _AnimatedEmptyStateIcon({required this.icon, this.color = kSleekAccent});

  final IconData icon;
  final Color color;

  @override
  State<_AnimatedEmptyStateIcon> createState() => _AnimatedEmptyStateIconState();
}

class _AnimatedEmptyStateIconState extends State<_AnimatedEmptyStateIcon> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 2600));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.of(context).disableAnimations) {
      _controller
        ..stop()
        ..value = 0;
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    final scheme = Theme.of(context).colorScheme;
    final iconBubble = Container(
      width: 54,
      height: 54,
      decoration: BoxDecoration(
        color: widget.color.withOpacity(.14),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: widget.color.withOpacity(.42)),
        boxShadow: [BoxShadow(color: widget.color.withOpacity(.12), blurRadius: 20, spreadRadius: 1)],
      ),
      child: Icon(widget.icon, color: widget.color, size: 29),
    );

    if (reduceMotion) return SizedBox(width: 92, height: 92, child: Center(child: iconBubble));
    return SizedBox(
      width: 92,
      height: 92,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Opacity(
            opacity: Theme.of(context).brightness == Brightness.dark ? .78 : .58,
            child: ColorFiltered(
              colorFilter: ColorFilter.mode(widget.color, BlendMode.srcATop),
              child: Lottie.asset('assets/lottie/empty_state.json', repeat: true, fit: BoxFit.contain),
            ),
          ),
          AnimatedBuilder(
            animation: _controller,
            child: iconBubble,
            builder: (context, child) {
              final phase = _controller.value * math.pi * 2;
              return Transform.translate(
                offset: Offset(0, math.sin(phase) * -3.2),
                child: Transform.rotate(angle: math.sin(phase + .6) * .018, child: child),
              );
            },
          ),
          IgnorePointer(
            child: Container(
              width: 68,
              height: 68,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: scheme.outline.withOpacity(.08)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class EmptyCard extends StatelessWidget {
  const EmptyCard({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
    this.action,
    this.actionLabel,
    this.animated = false,
    this.iconColor,
  });

  final IconData icon;
  final String title;
  final String body;
  final VoidCallback? action;
  final String? actionLabel;
  final bool animated;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final color = iconColor ?? kSleekAccent;
    return ExpressiveCard(
      child: Column(
        children: [
          if (animated)
            _AnimatedEmptyStateIcon(icon: icon, color: color)
          else
            Icon(icon, size: 42, color: color),
          const SizedBox(height: 12),
          Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
          const SizedBox(height: 6),
          Text(body, textAlign: TextAlign.center),
          if (action != null) ...[
            const SizedBox(height: 12),
            FilledButton(onPressed: action, child: Text(actionLabel ?? 'Add')),
          ],
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Accounts and categories management
// -----------------------------------------------------------------------------

class AccountTile extends StatelessWidget {
  const AccountTile({super.key, required this.account, this.onTap});
  final Account account;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final state = context.read<AppController>();
    final balanceColor = account.amount < 0 ? kSleekExpense : Theme.of(context).colorScheme.onSurface;
    return MotionTouchFeedback(
      enabled: onTap != null,
      scale: .985,
      child: ExpressiveCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      radius: 24,
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        leading: iconBubble(context, account.iconName, account.iconColor, size: 46),
        title: Text(account.name, style: const TextStyle(fontWeight: FontWeight.w900)),
        subtitle: Text(
          account.type == AccountType.credit
              ? 'Credit • Available ${state.format(account.availableCredit)}'
              : account.type == AccountType.savings
                  ? 'Savings Account'
                  : 'Cash Wallet',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: kSleekMuted, fontWeight: FontWeight.w700),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(state.format(account.amount), style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900, color: balanceColor)),
            const SizedBox(width: 6),
            Icon(Icons.chevron_right_rounded, color: Theme.of(context).colorScheme.onSurfaceVariant),
          ],
        ),
        onTap: onTap,
      ),
    ),
    );
  }
}


class AccountListScreen extends StatelessWidget {
  const AccountListScreen({super.key, this.filterType, this.title = 'Accounts'});

  final AccountType? filterType;
  final String title;

  bool _matches(Account account) {
    if (filterType == AccountType.savings) return account.type == AccountType.savings;
    return account.type != AccountType.savings;
  }

  AccountType get _initialType => filterType == AccountType.savings ? AccountType.savings : AccountType.regular;
  List<AccountType> get _allowedTypes => filterType == AccountType.savings
      ? const [AccountType.savings]
      : const [AccountType.regular, AccountType.credit];

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppController>();
    final visibleAccounts = state.accounts.where(_matches).toList();
    final emptyTitle = filterType == AccountType.savings ? 'No savings accounts' : 'No accounts';
    final emptyBody = filterType == AccountType.savings
        ? 'Create a savings account. Balance changes here do not create income, expense, or transaction history.'
        : 'Create your first account to start tracking money.';
    final empty = EmptyCard(
      icon: filterType == AccountType.savings ? Icons.savings_rounded : Icons.account_balance_wallet_rounded,
      title: emptyTitle,
      body: emptyBody,
      action: () => showAccountEditor(context, initialType: _initialType, allowedTypes: _allowedTypes),
      actionLabel: filterType == AccountType.savings ? 'Add savings account' : 'Add account',
    );

    return PageScaffold(
      title: title,
      actions: [
        IconButton(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => AccountReorderScreen(filterType: filterType))), icon: const Icon(Icons.swap_vert_rounded)),
        IconButton(onPressed: () => showAccountEditor(context, initialType: _initialType, allowedTypes: _allowedTypes), icon: const Icon(Icons.add_rounded)),
      ],
      child: filterType == AccountType.savings
          ? SavingsAccountsContent(accounts: visibleAccounts, empty: empty, allowedTypes: _allowedTypes)
          : ResponsiveListContent(
              itemCount: visibleAccounts.length,
              empty: empty,
              itemBuilder: (context, index) {
                final account = visibleAccounts[index];
                return AccountTile(account: account, onTap: () => showAccountEditor(context, account: account, allowedTypes: _allowedTypes));
              },
            ),
    );
  }
}


class SavingsAccountsContent extends StatefulWidget {
  const SavingsAccountsContent({super.key, required this.accounts, required this.empty, required this.allowedTypes});

  final List<Account> accounts;
  final Widget empty;
  final List<AccountType> allowedTypes;

  @override
  State<SavingsAccountsContent> createState() => _SavingsAccountsContentState();
}

class _SavingsAccountsContentState extends State<SavingsAccountsContent> {
  @override
  Widget build(BuildContext context) {
    return ResponsiveContent(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.accounts.isEmpty)
            widget.empty
          else
            ...widget.accounts.map(
              (account) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: AccountTile(
                  account: account,
                  onTap: () => showAccountEditor(context, account: account, allowedTypes: widget.allowedTypes),
                ),
              ),
            ),
          if (widget.accounts.isNotEmpty) const SizedBox(height: 120),
        ],
      ),
    );
  }
}

class AccountReorderScreen extends StatefulWidget {
  const AccountReorderScreen({super.key, this.filterType});
  final AccountType? filterType;

  @override
  State<AccountReorderScreen> createState() => _AccountReorderScreenState();
}

class _AccountReorderScreenState extends State<AccountReorderScreen> {
  late List<Account> items;

  bool _matches(Account account) {
    if (widget.filterType == AccountType.savings) return account.type == AccountType.savings;
    return account.type != AccountType.savings;
  }

  @override
  void initState() {
    super.initState();
    items = context.read<AppController>().accounts.where(_matches).toList();
  }

  @override
  Widget build(BuildContext context) {
    return PageScaffold(
      title: widget.filterType == AccountType.savings ? 'Reorder savings accounts' : 'Reorder accounts',
      actions: [
        IconButton(
          onPressed: () async {
            await context.read<AppController>().reorderAccounts(items);
            if (context.mounted) Navigator.pop(context);
          },
          icon: const Icon(Icons.check_rounded),
        )
      ],
      child: ReorderableListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
        itemCount: items.length,
        onReorder: (oldIndex, newIndex) {
          setState(() {
            if (newIndex > oldIndex) newIndex -= 1;
            final item = items.removeAt(oldIndex);
            items.insert(newIndex, item);
          });
        },
        itemBuilder: (context, index) => Padding(
          key: ValueKey(items[index].id),
          padding: const EdgeInsets.only(bottom: 10),
          child: AccountTile(account: items[index]),
        ),
      ),
    );
  }
}

Future<String?> showAccountEditor(
  BuildContext context, {
  Account? account,
  AccountType initialType = AccountType.regular,
  List<AccountType>? allowedTypes,
}) {
  return showKoinlyPopup<String>(
    context,
    maxWidth: 560,
    maxHeight: 720,
    child: AccountEditor(account: account, initialType: initialType, allowedTypes: allowedTypes),
  );
}

class AccountEditor extends StatefulWidget {
  const AccountEditor({super.key, this.account, this.initialType = AccountType.regular, this.allowedTypes});
  final Account? account;
  final AccountType initialType;
  final List<AccountType>? allowedTypes;

  @override
  State<AccountEditor> createState() => _AccountEditorState();
}

class _AccountEditorState extends State<AccountEditor> {
  final name = TextEditingController();
  final amount = TextEditingController();
  final creditLimit = TextEditingController();
  AccountType type = AccountType.regular;
  String icon = 'wallet';
  String color = kSleekAccentHex;

  List<AccountType> get allowedTypes => widget.allowedTypes ?? AccountType.values;

  List<SleekPillOption<AccountType>> get _typeOptions {
    return allowedTypes.map((accountType) {
      switch (accountType) {
        case AccountType.regular:
          return const SleekPillOption(value: AccountType.regular, label: 'Regular', icon: Icons.account_balance_wallet_rounded);
        case AccountType.credit:
          return const SleekPillOption(value: AccountType.credit, label: 'Credit', icon: Icons.credit_card_rounded);
        case AccountType.savings:
          return const SleekPillOption(value: AccountType.savings, label: 'Savings', icon: Icons.savings_rounded);
      }
    }).toList();
  }

  @override
  void initState() {
    super.initState();
    final a = widget.account;
    if (a != null) {
      name.text = a.name;
      amount.text = a.amount.toStringAsFixed(2);
      creditLimit.text = a.creditLimit.toStringAsFixed(2);
      type = allowedTypes.contains(a.type) ? a.type : allowedTypes.first;
      icon = a.iconName;
      color = a.iconColor;
    } else {
      type = allowedTypes.contains(widget.initialType) ? widget.initialType : allowedTypes.first;
      if (type == AccountType.savings) {
        name.text = 'Savings Account';
        icon = 'savings';
        color = '#A6E3A1';
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppController>();
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 18, 14, 14),
      child: KoinlyPopupContent(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.account == null ? 'Create account' : 'Edit account', textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900)),
            const SizedBox(height: 18),
            TextField(
              onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
              controller: name, decoration: const InputDecoration(labelText: 'Account name')),
            const SizedBox(height: 12),
            SleekPillSelector<AccountType>(
              options: _typeOptions,
              selected: type,
              onChanged: (v) => setState(() {
                type = v;
                if (v == AccountType.savings && icon == 'wallet') {
                  icon = 'savings';
                  color = '#A6E3A1';
                }
              }),
            ),
            const SizedBox(height: 12),
            TextField(
              onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
              controller: amount, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Balance')),
            if (type == AccountType.savings) ...[
              const SizedBox(height: 8),
              Text(
                'Changing this balance updates total accounts only. It does not create income, expense, or transaction history.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: kSleekMuted, fontWeight: FontWeight.w700),
              ),
            ],
            if (type == AccountType.credit) ...[
              const SizedBox(height: 12),
              TextField(
                onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
                controller: creditLimit, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Credit limit')),
            ],
            const SizedBox(height: 12),
            IconColorPicker(selectedIcon: icon, selectedColor: color, onChanged: (i, c) => setState(() { icon = i; color = c; })),
            const SizedBox(height: 18),
            Row(
              children: [
                if (widget.account != null)
                  Expanded(child: OutlinedButton(onPressed: () async { await state.deleteAccount(widget.account!.id); if (context.mounted) Navigator.pop(context); }, child: const Text('Delete'))),
                if (widget.account != null) const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: FilledButton(
                    onPressed: () async {
                      if (name.text.trim().isEmpty) return;
                      final now = DateTime.now();
                      final a = Account(
                        id: widget.account?.id ?? _uuid.v4(),
                        name: name.text.trim(),
                        type: type,
                        iconName: icon,
                        iconColor: color,
                        amount: double.tryParse(amount.text) ?? 0,
                        creditLimit: type == AccountType.credit ? (double.tryParse(creditLimit.text) ?? 0) : 0,
                        sequence: widget.account?.sequence ?? state.accounts.length,
                        createdOn: widget.account?.createdOn ?? now,
                        updatedOn: now,
                      );
                      await state.saveAccount(a);
                      if (context.mounted) Navigator.pop(context, a.id);
                    },
                    child: const Text('Save'),
                  ),
                ),
              ],
            )
          ],
        ),
      ),
    );
  }
}


class IconColorPicker extends StatelessWidget {
  const IconColorPicker({super.key, required this.selectedIcon, required this.selectedColor, required this.onChanged});
  final String selectedIcon;
  final String selectedColor;
  final void Function(String icon, String color) onChanged;

  static const icons = [
    'wallet', 'credit_card', 'bank', 'savings', 'cash', 'atm', 'receipt', 'calculator',
    'apparel', 'shopping_bag', 'cart', 'store', 'food', 'groceries', 'coffee', 'fastfood',
    'health', 'hospital', 'medicine', 'favorite', 'leisure', 'games', 'movie', 'music',
    'sports', 'fitness', 'book', 'school', 'car', 'bus', 'train', 'flight', 'origami_bird', 'anime', 'manga', 'collectibles', 'headphones', 'keyboard', 'laptop', 'monitor', 'mic', 'video', 'art', 'subscription', 'fuel',
    'home', 'house', 'apartment', 'utilities', 'water', 'wifi', 'phone', 'bolt',
    'gift', 'celebration', 'travel', 'pets', 'baby', 'beauty', 'salary', 'work',
    'business', 'investment', 'money', 'exchange', 'coupon', 'donation',
    'security', 'insurance', 'tools', 'construction', 'cleaning', 'laundry', 'parking',
    'calendar', 'time', 'flag', 'profile'
  ];
  static const colors = [
    kSleekAccentHex, '#38BDF8', '#0EA5E9', '#2563EB', '#1D4ED8', '#6366F1', '#8B5CF6', '#A855F7',
    '#D946EF', '#EC4899', '#F472B6', '#FB7185', '#EF4444', '#F97316', '#FB923C', '#F59E0B',
    '#FBC879', '#FACC15', '#A3E635', '#84CC16', '#22C55E', '#16A34A', '#10B981', '#14B8A6',
    '#2DD4BF', '#86E3CE', '#A6E3A1', '#89A7FF', '#B4A5FF', '#C4B5FD', '#F5A3A3', '#FFB5D0',
    '#FFB86B', '#94A3B8', '#64748B', '#475569', '#334155', '#1F2937', '#111827', '#F8FAFC'
  ];

  Future<void> _pickColor(BuildContext context) async {
    final result = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => ColorSelectionPage(selectedColor: selectedColor)),
    );
    if (result != null) onChanged(selectedIcon, result);
  }

  Future<void> _pickIcon(BuildContext context) async {
    final result = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => IconSelectionPage(selectedIcon: selectedIcon, selectedColor: selectedColor)),
    );
    if (result != null) onChanged(result, selectedColor);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 8, bottom: 10),
          child: Text(
            'APPEARANCE',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  letterSpacing: 3,
                  fontWeight: FontWeight.w900,
                  color: colorScheme.onSurface.withOpacity(.82),
                ),
          ),
        ),
        Row(
          children: [
            Expanded(
              child: _AppearanceButton(
                label: 'Color',
                onTap: () => _pickColor(context),
                preview: _ColorPreviewDot(color: selectedColor),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _AppearanceButton(
                label: 'Icon',
                onTap: () => _pickIcon(context),
                preview: _IconPreviewDot(icon: selectedIcon, color: selectedColor),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _AppearanceButton extends StatelessWidget {
  const _AppearanceButton({required this.label, required this.preview, required this.onTap});
  final String label;
  final Widget preview;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: colorScheme.surfaceContainerHighest.withOpacity(.52),
      borderRadius: BorderRadius.circular(24),
      child: MotionInkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 104),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: colorScheme.outline.withOpacity(.28), width: 1),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(.10), blurRadius: 18, offset: const Offset(0, 8))],
          ),
          child: Row(
            children: [
              preview,
              const SizedBox(width: 14),
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    label,
                    maxLines: 1,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Icon(Icons.edit_rounded, color: colorScheme.onSurface.withOpacity(.72)),
            ],
          ),
        ),
      ),
    );
  }
}

class _ColorPreviewDot extends StatelessWidget {
  const _ColorPreviewDot({required this.color});
  final String color;

  @override
  Widget build(BuildContext context) {
    final c = colorFromHex(color, fallback: Theme.of(context).colorScheme.primary);
    return Container(
      width: 54,
      height: 54,
      decoration: BoxDecoration(
        color: c,
        shape: BoxShape.circle,
        border: Border.all(color: Theme.of(context).colorScheme.onSurface.withOpacity(.10), width: 3),
        boxShadow: [BoxShadow(color: c.withOpacity(.35), blurRadius: 6, offset: const Offset(0, 2))],
      ),
    );
  }
}

class _IconPreviewDot extends StatelessWidget {
  const _IconPreviewDot({required this.icon, required this.color});
  final String icon;
  final String color;

  @override
  Widget build(BuildContext context) {
    final c = colorFromHex(color, fallback: Theme.of(context).colorScheme.primary);
    return Container(
      width: 54,
      height: 54,
      decoration: BoxDecoration(color: c, shape: BoxShape.circle),
      child: Center(child: iconGlyph(context, icon, color: Colors.white, size: 30, imageBackground: Colors.white.withOpacity(.92))),
    );
  }
}

class ColorSelectionPage extends StatelessWidget {
  const ColorSelectionPage({super.key, required this.selectedColor});
  final String selectedColor;

  String _normalizeColor(String value) {
    final cleaned = value.trim().replaceAll('#', '').replaceAll('0x', '').replaceAll('0X', '');
    final rgb = cleaned.length == 8 && cleaned.toUpperCase().startsWith('FF') ? cleaned.substring(2) : cleaned;
    if (RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(rgb)) return '#${rgb.toUpperCase()}';
    return '';
  }

  Future<String?> _showCustomColorOptions(BuildContext context) async {
    final initial = _normalizeColor(selectedColor).isEmpty ? kSleekAccentHex : _normalizeColor(selectedColor);

    final choice = await showKoinlyPopup<String>(
      context,
      maxWidth: 460,
      maxHeight: 420,
      child: Builder(
        builder: (dialogContext) {
          final dark = Theme.of(dialogContext).brightness == Brightness.dark;
          final handleColor = dark ? const Color(0xFF466057) : const Color(0xFFB7C9BF);
          return KoinlyPopupContent(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 44,
                  height: 5,
                  decoration: BoxDecoration(color: handleColor, borderRadius: BorderRadius.circular(999)),
                ),
                const SizedBox(height: 18),
                Text(
                  'Custom color',
                  style: Theme.of(dialogContext).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 6),
                Text(
                  'Choose how you want to create a custom color.',
                  textAlign: TextAlign.center,
                  style: Theme.of(dialogContext).textTheme.bodySmall?.copyWith(color: kSleekMuted, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 16),
                _CustomColorOptionCard(
                  icon: Icons.palette_rounded,
                  title: 'Color picker',
                  subtitle: 'Use color wheel, brightness, and HEX input',
                  onTap: () => Navigator.pop(dialogContext, 'wheel'),
                ),
                const SizedBox(height: 10),
                _CustomColorOptionCard(
                  icon: Icons.photo_library_rounded,
                  title: 'Pick from photo',
                  subtitle: 'Upload a photo and tap any pixel color',
                  onTap: () => Navigator.pop(dialogContext, 'photo'),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    child: const Text('Cancel'),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );

    if (!context.mounted || choice == null) return null;
    if (choice == 'wheel') {
      return Navigator.of(context).push<String>(
        MaterialPageRoute(builder: (_) => ColorWheelPickerPage(initialColor: initial)),
      );
    }
    if (choice == 'photo') {
      return Navigator.of(context).push<String>(
        MaterialPageRoute(builder: (_) => PhotoColorPickerPage(initialColor: initial)),
      );
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final selectedNormalized = _normalizeColor(selectedColor);
    final presetColors = IconColorPicker.colors.map(_normalizeColor).where((c) => c.isNotEmpty).toList();
    final customSelected = selectedNormalized.isNotEmpty && !presetColors.map((c) => c.toLowerCase()).contains(selectedNormalized.toLowerCase());
    final desktop = AppBreakpoints.isExpanded(context);

    return PageScaffold(
      title: 'Choose color',
      subtitle: 'Select the appearance color',
      child: ResponsiveContent(
        desktopMaxWidth: 920,
        padding: EdgeInsets.fromLTRB(desktop ? 24 : 16, desktop ? 18 : 12, desktop ? 24 : 16, 32),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final columns = desktop
                ? (width / 108).floor().clamp(7, 10).toInt()
                : width < 360
                    ? 4
                    : width < 500
                        ? 5
                        : 6;
            final spacing = desktop ? 18.0 : width < 360 ? 12.0 : 14.0;
            final itemSize = desktop
                ? 58.0
                : ((width - (spacing * (columns - 1))) / columns).clamp(52.0, 68.0).toDouble();

            final customCard = Material(
              color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(.52),
              borderRadius: BorderRadius.circular(22),
              child: MotionInkWell(
                borderRadius: BorderRadius.circular(22),
                onTap: () async {
                  final custom = await _showCustomColorOptions(context);
                  if (custom != null && context.mounted) Navigator.pop(context, custom);
                },
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: desktop ? 18 : 16, vertical: desktop ? 13 : 14),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(
                      color: customSelected ? kSleekAccent.withOpacity(.45) : Theme.of(context).colorScheme.outline.withOpacity(.24),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: desktop ? 44 : 48,
                        height: desktop ? 44 : 48,
                        decoration: BoxDecoration(
                          color: customSelected ? colorFromHex(selectedNormalized) : kSleekAccent.withOpacity(.18),
                          shape: BoxShape.circle,
                          border: Border.all(color: kSleekAccent.withOpacity(.45), width: 1.5),
                          boxShadow: customSelected ? [BoxShadow(color: colorFromHex(selectedNormalized).withOpacity(.32), blurRadius: 16)] : null,
                        ),
                        child: Icon(customSelected ? Icons.check_rounded : Icons.color_lens_rounded, color: Colors.white),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Custom color', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
                            const SizedBox(height: 2),
                            Text(
                              customSelected ? selectedNormalized : 'Color picker or pick from photo',
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: kSleekMuted, fontWeight: FontWeight.w700),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right_rounded),
                    ],
                  ),
                ),
              ),
            );

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (desktop)
                  Align(
                    alignment: Alignment.center,
                    child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 720), child: customCard),
                  )
                else
                  customCard,
                SizedBox(height: desktop ? 24 : 18),
                if (desktop) ...[
                  Text('Preset colors', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
                  const SizedBox(height: 4),
                  Text(
                    'Choose a ready-made accent color.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: kSleekMuted, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 14),
                ],
                Builder(
                  builder: (context) {
                    final cellWidth = ((width - (spacing * (columns - 1))) / columns).clamp(itemSize, width).toDouble();
                    return Wrap(
                      spacing: spacing,
                      runSpacing: spacing,
                      children: [
                        for (final color in presetColors)
                          SizedBox(
                            width: cellWidth,
                            height: itemSize,
                            child: Center(
                              child: _ColorChoiceDot(
                                color: color,
                                selected: selectedNormalized.toLowerCase() == color.toLowerCase(),
                                size: itemSize,
                                onTap: () => Navigator.pop(context, color),
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ],
            );
          },
        ),
      ),
    );
  }

}

class _CustomColorOptionCard extends StatelessWidget {
  const _CustomColorOptionCard({required this.icon, required this.title, required this.subtitle, required this.onTap});

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(.50),
      borderRadius: BorderRadius.circular(22),
      child: MotionInkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: Theme.of(context).colorScheme.outline.withOpacity(.28), width: .9),
          ),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: kSleekAccent.withOpacity(.16),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: kSleekAccent.withOpacity(.24)),
                ),
                child: Icon(icon, color: kSleekAccent),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: kSleekMuted, fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded),
            ],
          ),
        ),
      ),
    );
  }
}

class ColorWheelPickerPage extends StatefulWidget {
  const ColorWheelPickerPage({super.key, required this.initialColor});
  final String initialColor;

  @override
  State<ColorWheelPickerPage> createState() => _ColorWheelPickerPageState();
}

class _ColorWheelPickerPageState extends State<ColorWheelPickerPage> {
  late Color selectedColor;
  late TextEditingController hexController;
  double hue = 185;
  double saturation = .65;
  double value = .86;

  @override
  void initState() {
    super.initState();
    selectedColor = colorFromHex(widget.initialColor, fallback: kSleekAccent);
    final hsv = HSVColor.fromColor(selectedColor);
    hue = hsv.hue;
    saturation = hsv.saturation;
    value = hsv.value;
    hexController = TextEditingController(text: _hex(selectedColor));
  }

  @override
  void dispose() {
    hexController.dispose();
    super.dispose();
  }

  String _hex(Color color) => '#${color.value.toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';

  void _setColor(Color color, {bool updateHsv = true}) {
    setState(() {
      selectedColor = color.withAlpha(255);
      if (updateHsv) {
        final hsv = HSVColor.fromColor(selectedColor);
        hue = hsv.hue;
        saturation = hsv.saturation;
        value = hsv.value;
      }
      hexController.text = _hex(selectedColor);
    });
  }

  void _setFromHex(String input) {
    final cleaned = input.trim().replaceAll('#', '');
    if (!RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(cleaned)) return;
    _setColor(Color(int.parse('FF$cleaned', radix: 16)));
  }

  @override
  Widget build(BuildContext context) {
    final validHex = RegExp(r'^#[0-9A-Fa-f]{6}$').hasMatch(hexController.text);

    Widget previewCard() {
      return ExpressiveCard(
        child: Column(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              width: 78,
              height: 78,
              decoration: BoxDecoration(
                color: selectedColor,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white.withOpacity(.35), width: 2),
                boxShadow: [BoxShadow(color: selectedColor.withOpacity(.40), blurRadius: 22, spreadRadius: 1)],
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
              controller: hexController,
              textAlign: TextAlign.center,
              textCapitalization: TextCapitalization.characters,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9a-fA-F#]')),
                LengthLimitingTextInputFormatter(7),
              ],
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.tag_rounded),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.check_rounded),
                  onPressed: validHex ? () => _setFromHex(hexController.text) : null,
                ),
                labelText: 'HEX color',
                errorText: validHex ? null : 'Use #RRGGBB',
              ),
              onChanged: (value) {
                if (RegExp(r'^#?[0-9A-Fa-f]{6}$').hasMatch(value)) {
                  _setFromHex(value);
                } else {
                  setState(() {});
                }
              },
            ),
          ],
        ),
      );
    }

    Widget wheelCard({double? desktopWheelSize}) {
      final wheel = desktopWheelSize == null
          ? AspectRatio(
              aspectRatio: 1,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final wheelSize = Size(constraints.maxWidth, constraints.maxHeight);
                  return GestureDetector(
                    onPanDown: (details) => _pickFromWheel(details.localPosition, wheelSize),
                    onPanUpdate: (details) => _pickFromWheel(details.localPosition, wheelSize),
                    onTapDown: (details) => _pickFromWheel(details.localPosition, wheelSize),
                    child: CustomPaint(
                      painter: _HueSaturationWheelPainter(value: value),
                      foregroundPainter: _HueWheelHandlePainter(hue: hue, saturation: saturation),
                    ),
                  );
                },
              ),
            )
          : Center(
              child: SizedBox.square(
                dimension: desktopWheelSize,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final wheelSize = Size(constraints.maxWidth, constraints.maxHeight);
                    return GestureDetector(
                      onPanDown: (details) => _pickFromWheel(details.localPosition, wheelSize),
                      onPanUpdate: (details) => _pickFromWheel(details.localPosition, wheelSize),
                      onTapDown: (details) => _pickFromWheel(details.localPosition, wheelSize),
                      child: CustomPaint(
                        painter: _HueSaturationWheelPainter(value: value),
                        foregroundPainter: _HueWheelHandlePainter(hue: hue, saturation: saturation),
                      ),
                    );
                  },
                ),
              ),
            );

      return ExpressiveCard(
        child: Column(
          children: [
            wheel,
            const SizedBox(height: 16),
            _ValueSlider(
              color: selectedColor,
              value: value,
              onChanged: (v) {
                setState(() => value = v);
                _setColor(HSVColor.fromAHSV(1, hue, saturation, value).toColor(), updateHsv: false);
              },
            ),
          ],
        ),
      );
    }

    return PageScaffold(
      title: 'Color picker',
      subtitle: 'Create a custom color',
      child: ResponsiveContent(
        desktopMaxWidth: 1000,
        padding: EdgeInsets.fromLTRB(AppBreakpoints.isExpanded(context) ? 24 : 16, AppBreakpoints.isExpanded(context) ? 18 : 12, AppBreakpoints.isExpanded(context) ? 24 : 16, 32),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final desktopLayout = constraints.maxWidth >= 760;
            if (!desktopLayout) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  previewCard(),
                  const SizedBox(height: 14),
                  wheelCard(),
                  const SizedBox(height: 18),
                  FilledButton(
                    onPressed: validHex ? () => Navigator.pop(context, _hex(selectedColor)) : null,
                    child: const Text('Apply color'),
                  ),
                ],
              );
            }

            final wheelSize = math.min(430.0, math.max(330.0, constraints.maxWidth - 390.0)).toDouble();
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 320,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      previewCard(),
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(.34),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Theme.of(context).colorScheme.outline.withOpacity(.18)),
                        ),
                        child: Text(
                          'Drag on the wheel to choose hue and saturation, then fine-tune brightness.',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: kSleekMuted, fontWeight: FontWeight.w700, height: 1.4),
                        ),
                      ),
                      const SizedBox(height: 14),
                      FilledButton.icon(
                        onPressed: validHex ? () => Navigator.pop(context, _hex(selectedColor)) : null,
                        icon: const Icon(Icons.check_rounded),
                        label: const Text('Apply color'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 18),
                Expanded(child: wheelCard(desktopWheelSize: wheelSize)),
              ],
            );
          },
        ),
      ),
    );
  }

  void _pickFromWheel(Offset localPosition, Size wheelSize) {
    final size = wheelSize.shortestSide;
    final center = Offset(wheelSize.width / 2, wheelSize.height / 2);
    final dx = localPosition.dx - center.dx;
    final dy = localPosition.dy - center.dy;
    final radius = math.sqrt(dx * dx + dy * dy);
    final maxRadius = size / 2;
    if (radius > maxRadius) return;
    final angle = math.atan2(dy, dx);
    hue = (angle * 180 / math.pi + 360) % 360;
    saturation = (radius / maxRadius).clamp(0.0, 1.0).toDouble();
    _setColor(HSVColor.fromAHSV(1, hue, saturation, value).toColor(), updateHsv: false);
  }
}

class PhotoColorPickerPage extends StatefulWidget {
  const PhotoColorPickerPage({super.key, required this.initialColor});
  final String initialColor;

  @override
  State<PhotoColorPickerPage> createState() => _PhotoColorPickerPageState();
}

class _PhotoColorPickerPageState extends State<PhotoColorPickerPage> {
  late Color selectedColor;
  Uint8List? bytes;
  ui.Image? decodedImage;
  Uint8List? pixels;
  Offset? handle;

  @override
  void initState() {
    super.initState();
    selectedColor = colorFromHex(widget.initialColor, fallback: kSleekAccent);
  }

  @override
  void dispose() {
    decodedImage?.dispose();
    super.dispose();
  }

  String _hex(Color color) => '#${color.value.toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';

  Future<void> _pickPhoto() async {
    final picked = await FilePicker.platform.pickFiles(type: FileType.image, withData: true);
    if (picked == null) return;
    final data = picked.files.single.bytes ?? (picked.files.single.path == null ? null : await File(picked.files.single.path!).readAsBytes());
    if (data == null) return;

    final codec = await ui.instantiateImageCodec(data);
    final frame = await codec.getNextFrame();
    final image = frame.image;
    final byteData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);

    decodedImage?.dispose();
    setState(() {
      bytes = data;
      decodedImage = image;
      pixels = byteData?.buffer.asUint8List();
      handle = null;
    });
  }

  void _sampleColor(Offset pos, Size size) {
    final image = decodedImage;
    final raw = pixels;
    if (image == null || raw == null) return;

    final scale = math.min(size.width / image.width, size.height / image.height);
    final displayedWidth = image.width * scale;
    final displayedHeight = image.height * scale;
    final offset = Offset((size.width - displayedWidth) / 2, (size.height - displayedHeight) / 2);

    if (pos.dx < offset.dx || pos.dy < offset.dy || pos.dx > offset.dx + displayedWidth || pos.dy > offset.dy + displayedHeight) return;

    final x = ((pos.dx - offset.dx) / scale).floor().clamp(0, image.width - 1);
    final y = ((pos.dy - offset.dy) / scale).floor().clamp(0, image.height - 1);
    final index = ((y * image.width + x) * 4).toInt();
    if (index + 3 >= raw.length) return;

    setState(() {
      selectedColor = Color.fromARGB(255, raw[index], raw[index + 1], raw[index + 2]);
      handle = pos;
    });
  }

  @override
  Widget build(BuildContext context) {
    return PageScaffold(
      title: 'Pick from photo',
      subtitle: 'Tap or drag on a photo to sample color',
      child: ResponsiveContent(
        desktopMaxWidth: 900,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ExpressiveCard(
              child: Row(
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    width: 58,
                    height: 58,
                    decoration: BoxDecoration(
                      color: selectedColor,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white.withOpacity(.35), width: 2),
                      boxShadow: [BoxShadow(color: selectedColor.withOpacity(.40), blurRadius: 18)],
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_hex(selectedColor), style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
                        const SizedBox(height: 3),
                        Text('Selected custom color', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: kSleekMuted, fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: _pickPhoto,
              icon: const Icon(Icons.photo_library_rounded),
              label: Text(bytes == null ? 'Upload photo' : 'Change photo'),
            ),
            const SizedBox(height: 14),
            ExpressiveCard(
              padding: const EdgeInsets.all(14),
              child: bytes == null
                  ? EmptyCard(
                      icon: Icons.photo_library_rounded,
                      title: 'No photo selected',
                      body: 'Upload a photo, then tap or drag on it to pick a color.',
                    )
                  : ClipRRect(
                      borderRadius: BorderRadius.circular(18),
                      child: Container(
                        height: 300,
                        color: Theme.of(context).brightness == Brightness.dark ? kSleekSurfaceLow : kSleekLightBackground,
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final size = Size(constraints.maxWidth, constraints.maxHeight);
                            return GestureDetector(
                              onTapDown: (details) => _sampleColor(details.localPosition, size),
                              onPanDown: (details) => _sampleColor(details.localPosition, size),
                              onPanUpdate: (details) => _sampleColor(details.localPosition, size),
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  Image.memory(bytes!, fit: BoxFit.contain),
                                  if (handle != null)
                                    Positioned(
                                      left: handle!.dx - 12,
                                      top: handle!.dy - 12,
                                      child: Container(
                                        width: 24,
                                        height: 24,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          border: Border.all(color: Colors.white, width: 3),
                                          boxShadow: [BoxShadow(color: Colors.black.withOpacity(.45), blurRadius: 8)],
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                    ),
            ),
            const SizedBox(height: 18),
            FilledButton(
              onPressed: () => Navigator.pop(context, _hex(selectedColor)),
              child: const Text('Apply color'),
            ),
          ],
        ),
      ),
    );
  }
}

class _HueSaturationWheelPainter extends CustomPainter {
  const _HueSaturationWheelPainter({required this.value});
  final double value;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = SweepGradient(
          colors: const [
            Color(0xFFFF0000),
            Color(0xFFFFFF00),
            Color(0xFF00FF00),
            Color(0xFF00FFFF),
            Color(0xFF0000FF),
            Color(0xFFFF00FF),
            Color(0xFFFF0000),
          ],
        ).createShader(rect),
    );

    canvas.drawCircle(
      center,
      radius,
      Paint()..shader = RadialGradient(colors: [Colors.white, Colors.white.withOpacity(0)]).createShader(rect),
    );

    if (value < 1) {
      canvas.drawCircle(center, radius, Paint()..color = Colors.black.withOpacity(1 - value));
    }

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Colors.white.withOpacity(.22),
    );
  }

  @override
  bool shouldRepaint(covariant _HueSaturationWheelPainter oldDelegate) => oldDelegate.value != value;
}

class _HueWheelHandlePainter extends CustomPainter {
  const _HueWheelHandlePainter({required this.hue, required this.saturation});
  final double hue;
  final double saturation;

  @override
  void paint(Canvas canvas, Size size) {
    final radius = size.shortestSide / 2;
    final angle = hue * math.pi / 180;
    final handle = Offset(
      radius + math.cos(angle) * radius * saturation,
      radius + math.sin(angle) * radius * saturation,
    );
    canvas.drawCircle(handle, 9, Paint()..color = Colors.white);
    canvas.drawCircle(
      handle,
      6,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Colors.black.withOpacity(.55),
    );
  }

  @override
  bool shouldRepaint(covariant _HueWheelHandlePainter oldDelegate) => oldDelegate.hue != hue || oldDelegate.saturation != saturation;
}

class _ValueSlider extends StatelessWidget {
  const _ValueSlider({required this.color, required this.value, required this.onChanged});
  final Color color;
  final double value;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Brightness', style: Theme.of(context).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800, color: kSleekMuted)),
        const SizedBox(height: 8),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 16,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 12),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 20),
            activeTrackColor: color,
            inactiveTrackColor: Colors.white.withOpacity(.12),
            thumbColor: Colors.white,
          ),
          child: Slider(value: value, min: 0, max: 1, onChanged: onChanged),
        ),
      ],
    );
  }
}

class _ColorChoiceDot extends StatelessWidget {
  const _ColorChoiceDot({required this.color, required this.selected, required this.size, required this.onTap});

  final String color;
  final bool selected;
  final double size;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = colorFromHex(color, fallback: Theme.of(context).colorScheme.primary);
    return MotionInkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: size,
        height: size,
        padding: EdgeInsets.all(selected ? 5 : 4),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? Theme.of(context).colorScheme.onSurface : Theme.of(context).colorScheme.outline.withOpacity(.28),
            width: selected ? 3.2 : 1.2,
          ),
        ),
        child: Container(
          decoration: BoxDecoration(
            color: c,
            shape: BoxShape.circle,
            boxShadow: [BoxShadow(color: c.withOpacity(selected ? .42 : .18), blurRadius: selected ? 14 : 8, spreadRadius: selected ? 1 : 0)],
          ),
          child: selected ? const Icon(Icons.check_rounded, color: Colors.white, size: 28) : null,
        ),
      ),
    );
  }
}


class IconSelectionPage extends StatelessWidget {
  const IconSelectionPage({super.key, required this.selectedIcon, required this.selectedColor});
  final String selectedIcon;
  final String selectedColor;

  @override
  Widget build(BuildContext context) {
    final selectedColorValue = colorFromHex(selectedColor, fallback: Theme.of(context).colorScheme.primary);
    return PageScaffold(
      title: 'Choose icon',
      subtitle: 'Select the account or category icon',
      child: ResponsiveContent(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        child: Wrap(
          spacing: 12,
          runSpacing: 12,
          children: IconColorPicker.icons.map((icon) {
            final selected = selectedIcon == icon;
            return Material(
              color: selected ? selectedColorValue.withOpacity(.22) : Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(.48),
              borderRadius: BorderRadius.circular(20),
              child: MotionInkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: () => Navigator.pop(context, icon),
                child: Container(
                  width: 62,
                  height: 62,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: selected ? selectedColorValue : Theme.of(context).colorScheme.outline.withOpacity(.30),
                      width: selected ? 2.4 : 1.2,
                    ),
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      iconGlyph(context, icon, color: selected ? selectedColorValue : Theme.of(context).colorScheme.onSurface, size: 28, imageBackground: Colors.white.withOpacity(.92)),
                      if (selected)
                        Positioned(
                          right: 5,
                          bottom: 5,
                          child: Icon(Icons.check_circle_rounded, size: 16, color: selectedColorValue),
                        ),
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}


class CategoryTile extends StatelessWidget {
  const CategoryTile({super.key, required this.category, this.trailing, this.onTap});
  final Category category;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return MotionTouchFeedback(
      enabled: onTap != null,
      scale: .985,
      child: ExpressiveCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      radius: 24,
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        leading: iconBubble(context, category.iconName, category.iconColor),
        title: Text(category.name, style: const TextStyle(fontWeight: FontWeight.w800)),
        subtitle: Text(enumName(category.type)),
        trailing: trailing,
        onTap: onTap,
      ),
    ),
    );
  }
}

Future<String?> showCategoryEditor(
  BuildContext context, {
  Category? category,
  CategoryType? initialType,
  CategoryType? fixedType,
}) {
  return showKoinlyPopup<String>(
    context,
    maxWidth: 560,
    maxHeight: 720,
    child: CategoryEditor(category: category, initialType: initialType, fixedType: fixedType),
  );
}

class CategoryEditor extends StatefulWidget {
  const CategoryEditor({super.key, this.category, this.initialType, this.fixedType});
  final Category? category;
  final CategoryType? initialType;
  final CategoryType? fixedType;

  @override
  State<CategoryEditor> createState() => _CategoryEditorState();
}

class _CategoryEditorState extends State<CategoryEditor> {
  final name = TextEditingController();
  CategoryType type = CategoryType.expense;
  String icon = 'category';
  String color = kSleekAccentHex;

  @override
  void initState() {
    super.initState();
    final c = widget.category;
    if (c != null) {
      name.text = c.name;
      type = widget.fixedType ?? c.type;
      icon = c.iconName;
      color = c.iconColor;
    } else {
      type = widget.fixedType ?? widget.initialType ?? CategoryType.expense;
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppController>();
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 18, 14, 14),
      child: KoinlyPopupContent(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.category == null ? 'Create category' : 'Edit category', textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900)),
            const SizedBox(height: 18),
            TextField(
              onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
              controller: name, decoration: const InputDecoration(labelText: 'Category name')),
            const SizedBox(height: 12),
            if (widget.fixedType == null)
              SleekPillSelector<CategoryType>(
                options: const [
                  SleekPillOption(value: CategoryType.expense, label: 'Expense', icon: Icons.north_east_rounded),
                  SleekPillOption(value: CategoryType.income, label: 'Income', icon: Icons.south_west_rounded),
                ],
                selected: type,
                onChanged: (v) => setState(() => type = v),
              )
            else
              ExpressiveCard(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Row(
                  children: [
                    Icon(
                      type == CategoryType.income ? Icons.south_west_rounded : Icons.north_east_rounded,
                      color: type == CategoryType.income ? kSleekIncome : kSleekExpense,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      type == CategoryType.income ? 'Income category' : 'Expense category',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 12),
            IconColorPicker(selectedIcon: icon, selectedColor: color, onChanged: (i, c) => setState(() { icon = i; color = c; })),
            const SizedBox(height: 18),
            Row(children: [
              if (widget.category != null) Expanded(child: OutlinedButton(onPressed: () async { await state.deleteCategory(widget.category!.id); if (context.mounted) Navigator.pop(context); }, child: const Text('Delete'))),
              if (widget.category != null) const SizedBox(width: 12),
              Expanded(flex: 2, child: FilledButton(onPressed: () async {
                if (name.text.trim().isEmpty) return;
                final now = DateTime.now();
                final category = Category(id: widget.category?.id ?? _uuid.v4(), name: name.text.trim(), type: type, iconName: icon, iconColor: color, createdOn: widget.category?.createdOn ?? now, updatedOn: now);
                try {
                  await state.saveCategory(category);
                  if (context.mounted) Navigator.pop(context, category.id);
                } on StateError catch (error) {
                  if (context.mounted) showSnack(context, error.message);
                }
              }, child: const Text('Save'))),
            ]),
          ],
        ),
      ),
    );
  }
}


// -----------------------------------------------------------------------------
// Purchase plan
// -----------------------------------------------------------------------------

class PurchasePlanScreen extends StatelessWidget {
  const PurchasePlanScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppController>();
    final items = state.plannedPurchases;
    final total = items.fold<double>(0, (sum, item) => sum + item.amount);
    return PageScaffold(
      title: 'Plan',
      subtitle: '${items.length} ${items.length == 1 ? 'item' : 'items'} to buy later',
      actions: [
        if (items.isNotEmpty)
          Tooltip(
            message: 'Total planned price',
            child: Container(
              constraints: const BoxConstraints(minWidth: 92, maxWidth: 132),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Theme.of(context).colorScheme.outline.withOpacity(.16)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    'Total',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  Text(
                    state.format(total),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w900),
                  ),
                ],
              ),
            ),
          ),
        IconButton(
          tooltip: 'Add planned item',
          onPressed: () => showPlannedPurchaseEditor(context),
          icon: const Icon(Icons.add_rounded),
        ),
      ],
      child: ResponsiveListContent(
        itemCount: items.length,
        empty: EmptyCard(
          icon: Icons.event_note_rounded,
          title: 'Nothing planned yet',
          body: 'Add something you want to buy later, including its expected price and expense category.',
          action: () => showPlannedPurchaseEditor(context),
          actionLabel: 'Add item',
          animated: true,
        ),
        itemBuilder: (context, index) => PlannedPurchaseTile(item: items[index]),
      ),
    );
  }
}

Future<void> _confirmDeletePlannedPurchase(BuildContext context, PlannedPurchase item) async {
  final state = context.read<AppController>();
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Delete planned item?'),
      content: Text('“${item.name}” will be removed from your plan. Existing transactions are not affected.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          style: FilledButton.styleFrom(backgroundColor: kSleekExpense),
          child: const Text('Delete'),
        ),
      ],
    ),
  );
  if (confirmed != true) return;
  await state.deletePlannedPurchase(item.id);
  if (context.mounted) showSnack(context, 'Planned item deleted.');
}

class PlannedPurchaseTile extends StatelessWidget {
  const PlannedPurchaseTile({super.key, required this.item});

  final PlannedPurchase item;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppController>();
    final category = state.categoryOf(item.categoryId);
    final categoryName = category?.name ?? 'Missing category';
    final iconName = category?.iconName ?? 'category';
    final iconColor = category?.iconColor ?? kSleekAccentHex;

    final card = ExpressiveCard(
      padding: const EdgeInsets.fromLTRB(16, 16, 14, 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          iconBubble(context, iconName, iconColor),
          const SizedBox(width: 14),
          Expanded(
            child: MotionInkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: () => showPlannedPurchaseEditor(context, item: item),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '$categoryName • ${state.format(item.amount)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );

    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      clipBehavior: Clip.antiAlias,
      child: Slidable(
        key: ValueKey('planned-${item.id}'),
        groupTag: 'planned-purchases',
        closeOnScroll: true,
        startActionPane: ActionPane(
          motion: const ScrollMotion(),
          extentRatio: .28,
          dragDismissible: false,
          openThreshold: .14,
          closeThreshold: .08,
          children: [
            _KoinlySlidableAction(
              onPressed: (_) => showPurchasePlannedItemDialog(context, item),
              backgroundColor: kSleekAccent,
              foregroundColor: Colors.white,
              icon: Icons.shopping_cart_checkout_rounded,
              label: 'Buy',
            ),
          ],
        ),
        endActionPane: ActionPane(
          motion: const ScrollMotion(),
          extentRatio: .48,
          dragDismissible: false,
          openThreshold: .34,
          closeThreshold: .16,
          children: [
            _KoinlySlidableAction(
              onPressed: (_) => showPlannedPurchaseEditor(context, item: item),
              backgroundColor: Theme.of(context).colorScheme.primaryContainer,
              foregroundColor: Theme.of(context).colorScheme.onPrimaryContainer,
              icon: Icons.edit_rounded,
              label: 'Edit',
            ),
            _KoinlySlidableAction(
              onPressed: (_) => _confirmDeletePlannedPurchase(context, item),
              backgroundColor: kSleekExpense,
              foregroundColor: Colors.white,
              icon: Icons.delete_outline_rounded,
              label: 'Delete',
            ),
          ],
        ),
        child: card,
      ),
    );
  }
}

Future<void> showPlannedPurchaseEditor(
  BuildContext context, {
  PlannedPurchase? item,
}) async {
  await showKoinlyPopup<void>(
    context,
    maxWidth: 560,
    maxHeight: 600,
    child: PlannedPurchaseEditor(item: item),
  );
}

class PlannedPurchaseEditor extends StatefulWidget {
  const PlannedPurchaseEditor({super.key, this.item});

  final PlannedPurchase? item;

  @override
  State<PlannedPurchaseEditor> createState() => _PlannedPurchaseEditorState();
}

class _PlannedPurchaseEditorState extends State<PlannedPurchaseEditor> {
  final name = TextEditingController();
  final amount = TextEditingController();
  String? categoryId;

  @override
  void initState() {
    super.initState();
    final state = context.read<AppController>();
    final item = widget.item;
    if (item != null) {
      name.text = item.name;
      amount.text = item.amount.toStringAsFixed(2);
      categoryId = item.categoryId;
    } else {
      amount.text = '';
      categoryId = state.defaultExpenseCategoryId ??
          state.categories.where((category) => category.type == CategoryType.expense).firstOrNull?.id;
    }
  }

  @override
  void dispose() {
    name.dispose();
    amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppController>();
    final expenseCategories = state.categories.where((category) => category.type == CategoryType.expense).toList();
    final selectedCategory = expenseCategories.where((category) => category.id == categoryId).firstOrNull;

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 18, 14, 14),
      child: KoinlyPopupContent(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.item == null ? 'Add planned item' : 'Edit planned item',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 16),
            TextField(
              onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
              controller: name,
              textInputAction: TextInputAction.next,
              textCapitalization: TextCapitalization.sentences,
              maxLength: 100,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.shopping_bag_outlined),
                labelText: 'Item name',
                hintText: 'Example: Headphones',
                counterText: '',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
              controller: amount,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              textInputAction: TextInputAction.next,
              inputFormatters: [
                TextInputFormatter.withFunction((oldValue, newValue) {
                  final value = newValue.text;
                  if (value.isEmpty || RegExp(r'^\d*\.?\d*$').hasMatch(value)) return newValue;
                  return oldValue;
                }),
              ],
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.payments_outlined),
                labelText: 'Expected price',
              ),
            ),
            const SizedBox(height: 12),
            AppleSelectionField(
              label: 'Category',
              option: selectedCategory == null ? null : optionFromCategory(selectedCategory),
              emptyText: expenseCategories.isEmpty ? 'No expense categories available' : 'Choose expense category',
              onTap: () async {
                final selected = await showAppleWheelSelectionSheet(
                  context,
                  title: 'Choose Category',
                  selectedId: categoryId,
                  options: expenseCategories.map(optionFromCategory).toList(),
                  addActionLabel: 'Add category',
                  onAdd: () => showCategoryEditor(
                    context,
                    initialType: CategoryType.expense,
                    fixedType: CategoryType.expense,
                  ),
                );
                if (selected != null && mounted) setState(() => categoryId = selected);
              },
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                if (widget.item != null)
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () async {
                        await state.deletePlannedPurchase(widget.item!.id);
                        if (context.mounted) Navigator.pop(context);
                      },
                      child: const Text('Delete'),
                    ),
                  ),
                if (widget.item != null) const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: FilledButton(
                    onPressed: () async {
                      final itemName = name.text.trim();
                      final price = double.tryParse(amount.text.trim()) ?? 0;
                      if (itemName.isEmpty) return showSnack(context, 'Enter an item name.');
                      if (price <= 0) return showSnack(context, 'Enter a valid price.');
                      if (categoryId == null || !expenseCategories.any((category) => category.id == categoryId)) {
                        return showSnack(context, 'Choose an expense category.');
                      }
                      final now = DateTime.now();
                      final planned = PlannedPurchase(
                        id: widget.item?.id ?? _uuid.v4(),
                        name: itemName,
                        amount: price,
                        categoryId: categoryId!,
                        createdOn: widget.item?.createdOn ?? now,
                        updatedOn: now,
                      );
                      await state.savePlannedPurchase(planned);
                      if (context.mounted) Navigator.pop(context);
                    },
                    child: const Text('Save'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> showPurchasePlannedItemDialog(
  BuildContext context,
  PlannedPurchase item,
) async {
  final state = context.read<AppController>();
  final accountOptions = state.accounts;
  if (accountOptions.isEmpty) {
    showSnack(context, 'Add an account before purchasing a planned item.');
    return;
  }
  final category = state.categoryOf(item.categoryId);
  if (category == null || category.type != CategoryType.expense) {
    showSnack(context, 'Choose a valid expense category for this item first.');
    await showPlannedPurchaseEditor(context, item: item);
    return;
  }

  await showKoinlyPopup<void>(
    context,
    maxWidth: 520,
    maxHeight: 500,
    child: PurchasePlannedItemDialog(item: item),
  );
}

class PurchasePlannedItemDialog extends StatefulWidget {
  const PurchasePlannedItemDialog({super.key, required this.item});

  final PlannedPurchase item;

  @override
  State<PurchasePlannedItemDialog> createState() => _PurchasePlannedItemDialogState();
}

class _PurchasePlannedItemDialogState extends State<PurchasePlannedItemDialog> {
  String? accountId;
  bool purchasing = false;

  @override
  void initState() {
    super.initState();
    final state = context.read<AppController>();
    final options = state.accounts;
    accountId = state.defaultAccountId != null && options.any((account) => account.id == state.defaultAccountId)
        ? state.defaultAccountId
        : options.firstOrNull?.id;
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppController>();
    final accounts = state.accounts;
    final selectedAccount = accounts.where((account) => account.id == accountId).firstOrNull;
    final category = state.categoryOf(widget.item.categoryId);

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 18, 14, 14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Buy ${widget.item.name}',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          Text(
            '${category?.name ?? 'Expense'} • ${state.format(widget.item.amount)}',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 18),
          AppleSelectionField(
            label: 'Spend from',
            option: selectedAccount == null ? null : optionFromAccount(selectedAccount, state),
            emptyText: 'Choose account',
            onTap: purchasing
                ? () {}
                : () async {
                    final selected = await showAppleWheelSelectionSheet(
                      context,
                      title: 'Choose Account',
                      selectedId: accountId,
                      options: accounts.map((account) => optionFromAccount(account, state)).toList(),
                      addActionLabel: 'Add account',
                      onAdd: () => showAccountEditor(context, allowedTypes: AccountType.values),
                    );
                    if (selected != null && mounted) setState(() => accountId = selected);
                  },
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: purchasing ? null : () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: FilledButton(
                  onPressed: purchasing
                      ? null
                      : () async {
                          final selectedId = accountId;
                          if (selectedId == null || !accounts.any((account) => account.id == selectedId)) {
                            return showSnack(context, 'Choose an account.');
                          }
                          setState(() => purchasing = true);
                          try {
                            await state.purchasePlannedItem(widget.item, selectedId);
                            if (context.mounted) {
                              Navigator.pop(context);
                              showSnack(context, '${widget.item.name} added to transactions.');
                            }
                          } on StateError catch (error) {
                            if (mounted) {
                              setState(() => purchasing = false);
                              showSnack(context, error.message);
                            }
                          } catch (_) {
                            if (mounted) {
                              setState(() => purchasing = false);
                              showSnack(context, 'Could not complete the purchase.');
                            }
                          }
                        },
                  child: Text(purchasing ? 'Purchasing…' : 'Purchase'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Transactions and filters
// -----------------------------------------------------------------------------

class TransactionListScreen extends StatelessWidget {
  const TransactionListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppController>();
    final txs = state.transactionListTransactions();
    return PageScaffold(
      title: 'Transaction',
      subtitle: '${txs.length} records • ${state.activeRange().label}',
      actions: [
        IconButton(onPressed: () => showDateRangeSheet(context), icon: const Icon(Icons.date_range_rounded)),
        IconButton(onPressed: () => showFilterSheet(context), icon: const Icon(Icons.filter_alt_rounded)),
      ],
      child: ResponsiveListContent(
        header: [ActiveFilterChips(state: state)],
        itemCount: txs.length,
        empty: EmptyCard(icon: Icons.receipt_long_rounded, title: 'No transactions', body: 'Create a transaction or change filters.', action: () => showTransactionEditor(context), actionLabel: 'Add transaction', animated: true),
        itemBuilder: (context, index) => TransactionTile(tx: txs[index]),
      ),
    );
  }
}

class ActiveFilterChips extends StatelessWidget {
  const ActiveFilterChips({super.key, required this.state});
  final AppController state;

  @override
  Widget build(BuildContext context) {
    final chips = <Widget>[];
    for (final id in state.filterAccountIds) {
      chips.add(InputChip(label: Text(state.accountOf(id)?.name ?? 'Account'), onDeleted: () => state.saveFilters(accounts: state.filterAccountIds.where((e) => e != id).toList())));
    }
    for (final id in state.filterCategoryIds) {
      chips.add(InputChip(label: Text(state.categoryOf(id)?.name ?? 'Category'), onDeleted: () => state.saveFilters(categories: state.filterCategoryIds.where((e) => e != id).toList())));
    }
    for (final type in state.filterTypes) {
      chips.add(InputChip(label: Text(enumName(type)), onDeleted: () => state.saveFilters(types: state.filterTypes.where((e) => e != type).toList())));
    }
    if (chips.isEmpty) return const SizedBox.shrink();
    chips.add(TextButton(onPressed: state.clearFilters, child: const Text('Clear all')));
    return Padding(padding: const EdgeInsets.only(bottom: 12), child: Wrap(spacing: 8, runSpacing: 8, children: chips));
  }
}

Future<void> _duplicateTransaction(BuildContext context, MoneyTransaction tx) async {
  if (tx.isLoanTransaction) {
    showSnack(context, 'Loan-linked transactions cannot be duplicated.');
    return;
  }
  final state = context.read<AppController>();
  final now = DateTime.now();
  final range = tx.endOn == null ? null : tx.effectiveEndOn.difference(tx.createdOn);
  final duplicate = MoneyTransaction(
    id: _uuid.v4(),
    type: tx.type,
    amount: tx.amount,
    title: tx.title,
    notes: tx.notes,
    categoryId: tx.categoryId,
    fromAccountId: tx.fromAccountId,
    toAccountId: tx.toAccountId,
    imagePath: tx.imagePath,
    excludeFromReports: tx.excludeFromReports,
    createdOn: now,
    endOn: range == null ? null : now.add(range),
    updatedOn: now,
  );
  await state.addTransaction(duplicate);
  if (context.mounted) showSnack(context, 'Transaction duplicated and added.');
}

Future<void> _confirmDeleteTransaction(BuildContext context, MoneyTransaction tx) async {
  final state = context.read<AppController>();
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Delete transaction?'),
      content: Text(
        tx.isLoanTransaction
            ? 'This transaction is linked to a loan. Deleting it will update the linked loan record.'
            : 'This transaction will be removed and the account balance will be recalculated.',
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          style: FilledButton.styleFrom(backgroundColor: kSleekExpense),
          child: const Text('Delete'),
        ),
      ],
    ),
  );
  if (confirmed != true) return;
  if (tx.isLoanTransaction) {
    await state.deleteLinkedLoanTransaction(tx);
  } else {
    await state.deleteTransaction(tx.id);
  }
  if (context.mounted) showSnack(context, 'Transaction deleted.');
}

class TransactionTile extends StatelessWidget {
  const TransactionTile({super.key, required this.tx});
  final MoneyTransaction tx;

  @override
  Widget build(BuildContext context) {
    final state = context.read<AppController>();
    final category = state.categoryOf(tx.categoryId);
    final account = state.accountOf(tx.fromAccountId);
    final toAccount = tx.toAccountId == null ? null : state.accountOf(tx.toAccountId!);
    final amountPrefix = tx.type == MoneyTransactionType.expense ? '-' : tx.type == MoneyTransactionType.income ? '+' : '';
    final amountColor = tx.type == MoneyTransactionType.expense ? kSleekExpense : tx.type == MoneyTransactionType.income ? kSleekIncome : kSleekAccent;
    final savedTitle = tx.title.trim();
    final title = tx.type == MoneyTransactionType.transfer
        ? '${account?.name ?? ''} → ${toAccount?.name ?? ''}'
        : savedTitle.isNotEmpty
            ? savedTitle
            : category?.name ?? 'Unknown';
    final subtitleParts = <String>[
      if (tx.type != MoneyTransactionType.transfer && savedTitle.isNotEmpty && category != null) category.name,
      transactionDateTimeLabel(tx),
      if (tx.notes.trim().isNotEmpty) tx.notes.trim(),
    ];

    final tile = MotionTouchFeedback(
      enabled: true,
      scale: .985,
      child: ExpressiveCard(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        radius: 24,
        child: ListTile(
          contentPadding: EdgeInsets.zero,
          leading: tx.type == MoneyTransactionType.transfer
              ? iconBubble(context, 'exchange', '#38BDF8', size: 44)
              : iconBubble(context, category?.iconName ?? 'category', category?.iconColor ?? kSleekAccentHex, size: 44),
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
          subtitle: Text(
            subtitleParts.join(' • '),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: kSleekMuted, fontWeight: FontWeight.w700),
          ),
          trailing: Text(
            '$amountPrefix${state.format(tx.amount)}',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900, color: amountColor),
          ),
          onTap: () => showTransactionEditor(context, transaction: tx),
        ),
      ),
    );

    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      clipBehavior: Clip.antiAlias,
      child: Slidable(
        key: ValueKey('transaction-${tx.id}'),
        groupTag: 'transactions',
        closeOnScroll: true,
        startActionPane: tx.isLoanTransaction
            ? null
            : ActionPane(
                motion: const ScrollMotion(),
                extentRatio: .28,
                dragDismissible: false,
                // The start pane is only 28% wide. Its snap-open threshold must
                // stay below that maximum extent; the old .34 threshold could
                // never be reached, so a left-to-right Duplicate swipe always
                // snapped closed as soon as the finger was released.
                openThreshold: .14,
                closeThreshold: .08,
                children: [
                  _KoinlySlidableAction(
                    onPressed: (_) => _duplicateTransaction(context, tx),
                    backgroundColor: kSleekAccent,
                    foregroundColor: Colors.white,
                    icon: Icons.content_copy_rounded,
                    label: 'Duplicate',
                  ),
                ],
              ),
        endActionPane: ActionPane(
          motion: const ScrollMotion(),
          extentRatio: .48,
          dragDismissible: false,
          openThreshold: .34,
          closeThreshold: .16,
          children: [
            _KoinlySlidableAction(
              onPressed: (_) => showTransactionEditor(context, transaction: tx),
              backgroundColor: Theme.of(context).colorScheme.primaryContainer,
              foregroundColor: Theme.of(context).colorScheme.onPrimaryContainer,
              icon: Icons.edit_rounded,
              label: 'Edit',
            ),
            _KoinlySlidableAction(
              onPressed: (_) => _confirmDeleteTransaction(context, tx),
              backgroundColor: kSleekExpense,
              foregroundColor: Colors.white,
              icon: Icons.delete_outline_rounded,
              label: 'Delete',
            ),
          ],
        ),
        child: tile,
      ),
    );
  }
}

String transactionDateSpanLabel(DateTime start, DateTime end) {
  if (isSameCalendarDay(start, end)) return DateFormat('MMM d, yyyy').format(start);
  if (start.year == end.year && start.month == end.month) {
    return '${DateFormat('MMM d').format(start)} → ${DateFormat('d, yyyy').format(end)}';
  }
  if (start.year == end.year) {
    return '${DateFormat('MMM d').format(start)} → ${DateFormat('MMM d, yyyy').format(end)}';
  }
  return '${DateFormat('MMM d, yyyy').format(start)} → ${DateFormat('MMM d, yyyy').format(end)}';
}

String transactionTimeSpanLabel(DateTime start, DateTime end, {bool forceRange = false}) {
  final startLabel = DateFormat('h:mm a').format(start);
  final sameMinute = start.hour == end.hour && start.minute == end.minute;
  if (!forceRange && sameMinute) return startLabel;
  return '$startLabel → ${DateFormat('h:mm a').format(end)}';
}

String transactionDateTimeLabel(MoneyTransaction transaction) {
  final end = transaction.effectiveEndOn;
  final hasTimeRange = transaction.endOn != null &&
      (transaction.createdOn.hour != end.hour || transaction.createdOn.minute != end.minute);
  return '${transactionDateSpanLabel(transaction.createdOn, end)} • ${transactionTimeSpanLabel(transaction.createdOn, end, forceRange: hasTimeRange)}';
}

Future<void> showTransactionEditor(BuildContext context, {MoneyTransaction? transaction, Category? lockedCategory}) async {
  await showKoinlyPopup<void>(
    context,
    maxWidth: 560,
    maxHeight: 700,
    child: TransactionEditor(transaction: transaction, lockedCategory: lockedCategory),
  );
}

class TransactionEditor extends StatefulWidget {
  const TransactionEditor({super.key, this.transaction, this.lockedCategory});
  final MoneyTransaction? transaction;
  final Category? lockedCategory;

  @override
  State<TransactionEditor> createState() => _TransactionEditorState();
}

class _TransactionEditorState extends State<TransactionEditor> {
  final title = TextEditingController();
  final notes = TextEditingController();
  final amount = TextEditingController();
  final amountFocus = FocusNode();
  MoneyTransactionType type = MoneyTransactionType.expense;
  String? categoryId;
  String? fromAccountId;
  String? toAccountId;
  DateTime selectedDate = DateTime.now();
  DateTime selectedEndDate = DateTime.now();
  bool dateRangeEnabled = false;
  bool timeRangeEnabled = false;
  bool _amountHasFocus = false;
  bool busy = false;

  @override
  void initState() {
    super.initState();
    amountFocus.addListener(_handleAmountFocusChanged);
    final state = context.read<AppController>();
    final tx = widget.transaction;
    if (tx != null) {
      title.text = tx.title;
      notes.text = tx.notes;
      amount.text = tx.amount.toStringAsFixed(2);
      type = tx.type;
      categoryId = tx.categoryId;
      fromAccountId = tx.fromAccountId;
      toAccountId = tx.toAccountId;
      selectedDate = tx.createdOn;
      selectedEndDate = tx.effectiveEndOn;
      dateRangeEnabled = tx.endOn != null && !isSameCalendarDay(tx.createdOn, tx.effectiveEndOn);
      timeRangeEnabled = tx.endOn != null &&
          (tx.createdOn.hour != tx.effectiveEndOn.hour || tx.createdOn.minute != tx.effectiveEndOn.minute);
    } else {
      selectedEndDate = selectedDate;
      type = widget.lockedCategory?.type == CategoryType.income ? MoneyTransactionType.income : MoneyTransactionType.expense;
      categoryId = widget.lockedCategory?.id ?? (type == MoneyTransactionType.income ? state.defaultIncomeCategoryId : state.defaultExpenseCategoryId);
      fromAccountId = state.defaultAccountId ?? state.operatingAccounts.firstOrNull?.id;
    }
  }

  void _handleAmountFocusChanged() {
    if (!mounted || _amountHasFocus == amountFocus.hasFocus) return;
    setState(() => _amountHasFocus = amountFocus.hasFocus);
  }

  void _dismissAmountFocus() {
    amountFocus.unfocus();
    FocusScope.of(context).unfocus();
  }

  DateTime _withDateAndTime(DateTime date, TimeOfDay time) =>
      DateTime(date.year, date.month, date.day, time.hour, time.minute);

  @override
  void dispose() {
    amountFocus.removeListener(_handleAmountFocusChanged);
    amountFocus.dispose();
    title.dispose();
    notes.dispose();
    amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppController>();
    final scheme = Theme.of(context).colorScheme;
    final isLoanTransaction = widget.transaction?.isLoanTransaction ?? false;
    final regularAccountOptions = state.operatingAccounts.isEmpty ? state.accounts : state.operatingAccounts;
    final transferFromOptions = state.accounts.where((a) => a.id != toAccountId).toList();
    final transferToOptions = state.accounts.where((a) => a.id != fromAccountId).toList();
    final accountOptions = type == MoneyTransactionType.transfer ? state.accounts : regularAccountOptions;
    final fromAccount = state.accounts.where((a) => a.id == fromAccountId).firstOrNull;
    final toAccount = state.accounts.where((a) => a.id == toAccountId).firstOrNull;
    final relevantCategories = state.categories.where((c) => c.type == (type == MoneyTransactionType.income ? CategoryType.income : CategoryType.expense)).toList();
    if (!isLoanTransaction && type == MoneyTransactionType.transfer) categoryId = '';
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 18, 14, 14),
      child: KoinlyPopupContent(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.transaction == null ? 'Add transaction' : 'Edit transaction', textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
            const SizedBox(height: 12),
            if (isLoanTransaction)
              SleekPillSelector<MoneyTransactionType>(
                options: [
                  SleekPillOption(value: type, label: 'Loan', icon: Icons.account_balance_rounded),
                ],
                selected: type,
                onChanged: (_) => _dismissAmountFocus(),
              )
            else
              SleekPillSelector<MoneyTransactionType>(
                options: const [
                  SleekPillOption(value: MoneyTransactionType.expense, label: 'Expense', icon: Icons.north_east_rounded),
                  SleekPillOption(value: MoneyTransactionType.income, label: 'Income', icon: Icons.south_west_rounded),
                  SleekPillOption(value: MoneyTransactionType.transfer, label: 'Transfer', icon: Icons.swap_horiz_rounded),
                ],
                selected: type,
                onChanged: (v) {
                  _dismissAmountFocus();
                  setState(() {
                    type = v;
                    if (type == MoneyTransactionType.income || type == MoneyTransactionType.expense) {
                      final targetType = type == MoneyTransactionType.income ? CategoryType.income : CategoryType.expense;
                      final newCategories = state.categories.where((c) => c.type == targetType).toList();
                      categoryId = type == MoneyTransactionType.income
                          ? state.defaultIncomeCategoryId ?? newCategories.firstOrNull?.id
                          : state.defaultExpenseCategoryId ?? newCategories.firstOrNull?.id;
                      final regularOptions = state.operatingAccounts.isEmpty ? state.accounts : state.operatingAccounts;
                      if (fromAccountId == null || regularOptions.where((a) => a.id == fromAccountId).firstOrNull == null) {
                        fromAccountId = state.defaultAccountId ?? regularOptions.firstOrNull?.id;
                      }
                      toAccountId = null;
                    } else {
                      categoryId = '';
                      fromAccountId = fromAccountId ?? state.accounts.firstOrNull?.id;
                      if (toAccountId == fromAccountId) toAccountId = null;
                    }
                  });
                },
              ),
            const SizedBox(height: 12),
            if (type != MoneyTransactionType.transfer) ...[
              TextField(
                onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
                controller: title,
                readOnly: isLoanTransaction,
                textInputAction: TextInputAction.next,
                textCapitalization: TextCapitalization.sentences,
                maxLength: 100,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.title_rounded),
                  labelText: 'Title',
                  hintText: 'Example: Lunch, Salary, Groceries',
                  counterText: '',
                ),
              ),
              const SizedBox(height: 12),
            ],
            TextField(
              onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
              controller: amount,
              focusNode: amountFocus,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              textInputAction: TextInputAction.next,
              textAlign: TextAlign.end,
              inputFormatters: [
                TextInputFormatter.withFunction((oldValue, newValue) {
                  final text = newValue.text;
                  if (text.isEmpty || RegExp(r'^\d*\.?\d*$').hasMatch(text)) return newValue;
                  return oldValue;
                }),
              ],
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w900),
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.calculate_rounded),
                labelText: 'Amount',
                hintText: _amountHasFocus ? null : '0',
                hintStyle: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      color: scheme.onSurfaceVariant.withOpacity(.72),
                      fontWeight: FontWeight.w900,
                    ),
              ),
            ),
            const SizedBox(height: 12),
            if (isLoanTransaction)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(left: 4, bottom: 6),
                    child: Text(
                      'Category',
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                            color: scheme.onSurfaceVariant,
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                  ),
                  ExpressiveCard(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                    child: Row(
                      children: [
                        Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: kSleekAccent.withOpacity(.13),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: kSleekAccent.withOpacity(.20)),
                          ),
                          child: const Icon(Icons.account_balance_rounded, color: kSleekAccent),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Loan', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
                              const SizedBox(height: 2),
                              Text(
                                widget.transaction?.linkedEntityType == 'loan_payments' ? 'Loan repayment' : 'Loan disbursal',
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: kSleekMuted, fontWeight: FontWeight.w700),
                              ),
                            ],
                          ),
                        ),
                        Icon(Icons.lock_outline_rounded, color: scheme.onSurfaceVariant),
                      ],
                    ),
                  ),
                ],
              )
            else if (type != MoneyTransactionType.transfer && widget.lockedCategory == null)
              AppleSelectionField(
                label: 'Category',
                option: relevantCategories.where((c) => c.id == categoryId).firstOrNull == null ? null : optionFromCategory(relevantCategories.where((c) => c.id == categoryId).first),
                emptyText: 'Choose category',
                onTap: () async {
                  _dismissAmountFocus();
                  final categoryType = type == MoneyTransactionType.income ? CategoryType.income : CategoryType.expense;
                  final selected = await showAppleWheelSelectionSheet(
                    context,
                    title: 'Choose Category',
                    selectedId: categoryId,
                    options: relevantCategories.map(optionFromCategory).toList(),
                    addActionLabel: 'Add category',
                    onAdd: () => showCategoryEditor(
                      context,
                      initialType: categoryType,
                      fixedType: categoryType,
                    ),
                  );
                  if (selected != null) setState(() => categoryId = selected);
                },
              ),
            if (widget.lockedCategory != null)
              ExpressiveCard(padding: const EdgeInsets.all(12), child: Row(children: [iconBubble(context, widget.lockedCategory!.iconName, widget.lockedCategory!.iconColor), const SizedBox(width: 12), Expanded(child: Text(widget.lockedCategory!.name, style: const TextStyle(fontWeight: FontWeight.w800)))])),
            const SizedBox(height: 12),
            AppleSelectionField(
              label: type == MoneyTransactionType.transfer ? 'From account' : 'Account',
              option: fromAccount == null ? null : optionFromAccount(fromAccount, state),
              emptyText: 'Choose account',
              onTap: () async {
                _dismissAmountFocus();
                final selected = await showAppleWheelSelectionSheet(
                  context,
                  title: type == MoneyTransactionType.transfer ? 'Choose From Account' : 'Choose Account',
                  selectedId: fromAccountId,
                  options: (type == MoneyTransactionType.transfer ? transferFromOptions : accountOptions).map((a) => optionFromAccount(a, state)).toList(),
                  addActionLabel: 'Add account',
                  onAdd: () => showAccountEditor(
                    context,
                    allowedTypes: type == MoneyTransactionType.transfer
                        ? AccountType.values
                        : const [AccountType.regular, AccountType.credit],
                  ),
                );
                if (selected != null) {
                  setState(() {
                    fromAccountId = selected;
                    if (toAccountId == selected) toAccountId = null;
                  });
                }
              },
            ),
            if (type == MoneyTransactionType.transfer) ...[
              const SizedBox(height: 12),
              AppleSelectionField(
                label: 'To account',
                option: toAccount == null ? null : optionFromAccount(toAccount, state),
                emptyText: 'Choose destination account',
                onTap: () async {
                  _dismissAmountFocus();
                  final selected = await showAppleWheelSelectionSheet(
                    context,
                    title: 'Choose To Account',
                    selectedId: toAccountId,
                    options: transferToOptions.map((a) => optionFromAccount(a, state)).toList(),
                    addActionLabel: 'Add account',
                    onAdd: () => showAccountEditor(context, allowedTypes: AccountType.values),
                  );
                  if (selected != null) {
                    setState(() {
                      toAccountId = selected;
                      if (fromAccountId == selected) fromAccountId = null;
                    });
                  }
                },
              ),
            ],
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () async {
                _dismissAmountFocus();
                final selection = await pickTransactionDateSelection(
                  context,
                  selectedDate,
                  selectedEndDate,
                  useRange: dateRangeEnabled,
                );
                if (!mounted || selection == null) return;
                final startTime = TimeOfDay.fromDateTime(selectedDate);
                final endTime = TimeOfDay.fromDateTime(selectedEndDate);
                var resetTimeRange = false;
                final newStart = _withDateAndTime(selection.start, startTime);
                var newEnd = _withDateAndTime(
                  selection.useRange ? selection.end : selection.start,
                  timeRangeEnabled ? endTime : startTime,
                );
                if (!selection.useRange && timeRangeEnabled && !newEnd.isAfter(newStart)) {
                  resetTimeRange = true;
                  newEnd = newStart;
                }
                setState(() {
                  dateRangeEnabled = selection.useRange;
                  if (resetTimeRange) timeRangeEnabled = false;
                  selectedDate = newStart;
                  selectedEndDate = newEnd;
                });
                if (resetTimeRange && mounted) {
                  showSnack(context, 'Time range was reset because its end time was not after the selected date');
                }
              },
              icon: Icon(dateRangeEnabled ? Icons.date_range_rounded : Icons.calendar_today_rounded),
              label: Text(dateRangeEnabled
                  ? transactionDateSpanLabel(selectedDate, selectedEndDate)
                  : DateFormat('MMM d, yyyy').format(selectedDate)),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () async {
                _dismissAmountFocus();
                final selection = await pickTransactionTimeSelection(
                  context,
                  TimeOfDay.fromDateTime(selectedDate),
                  TimeOfDay.fromDateTime(selectedEndDate),
                  useRange: timeRangeEnabled,
                  datesSpanMultipleDays: dateRangeEnabled && !isSameCalendarDay(selectedDate, selectedEndDate),
                );
                if (!mounted || selection == null) return;
                final start = _withDateAndTime(selectedDate, selection.start);
                final endDate = dateRangeEnabled ? selectedEndDate : selectedDate;
                final end = _withDateAndTime(endDate, selection.useRange ? selection.end : selection.start);
                setState(() {
                  timeRangeEnabled = selection.useRange;
                  selectedDate = start;
                  selectedEndDate = dateRangeEnabled || selection.useRange ? end : start;
                });
              },
              icon: Icon(timeRangeEnabled ? Icons.timelapse_rounded : Icons.schedule_rounded),
              label: Text(transactionTimeSpanLabel(selectedDate, selectedEndDate, forceRange: timeRangeEnabled)),
            ),
            const SizedBox(height: 12),
            TextField(
              onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
              controller: notes, minLines: 1, maxLines: 3, decoration: const InputDecoration(labelText: 'Notes')),
            const SizedBox(height: 18),
            Row(children: [
              if (widget.transaction != null) Expanded(child: OutlinedButton(onPressed: () async {
                if (isLoanTransaction) {
                  await state.deleteLinkedLoanTransaction(widget.transaction!);
                } else {
                  await state.deleteTransaction(widget.transaction!.id);
                }
                if (context.mounted) Navigator.pop(context);
              }, child: const Text('Delete'))),
              if (widget.transaction != null) const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: FilledButton(
                  onPressed: busy
                      ? null
                      : () async {
                          _dismissAmountFocus();
                          final value = double.tryParse(amount.text) ?? 0;
                          if (value <= 0) return showSnack(context, 'Enter a valid amount');
                          final transactionTitle = title.text.trim();
                          if (type != MoneyTransactionType.transfer && transactionTitle.isEmpty) return showSnack(context, 'Enter a transaction title');
                          if (fromAccountId == null) return showSnack(context, 'Select an account');
                          if (type == MoneyTransactionType.transfer && (toAccountId == null || toAccountId == fromAccountId)) return showSnack(context, 'Select a different destination account');
                          if (!isLoanTransaction && type != MoneyTransactionType.transfer && categoryId == null) return showSnack(context, 'Select a category');
                          final rangeRequested = dateRangeEnabled || timeRangeEnabled;
                          if (rangeRequested && selectedEndDate.isBefore(selectedDate)) return showSnack(context, 'The end of the range must be after the start');
                          final hasEffectiveRange = rangeRequested && selectedEndDate.isAfter(selectedDate);
                          setState(() => busy = true);
                          try {
                            final tx = MoneyTransaction(
                              id: widget.transaction?.id ?? _uuid.v4(),
                              type: type,
                              amount: value,
                              title: type == MoneyTransactionType.transfer ? '' : transactionTitle,
                              notes: notes.text.trim(),
                              categoryId: type == MoneyTransactionType.transfer ? '' : (categoryId ?? ''),
                              fromAccountId: fromAccountId!,
                              toAccountId: type == MoneyTransactionType.transfer ? toAccountId : null,
                              imagePath: widget.transaction?.imagePath ?? '',
                              excludeFromReports: widget.transaction?.excludeFromReports ?? false,
                              linkedEntityType: widget.transaction?.linkedEntityType,
                              linkedEntityId: widget.transaction?.linkedEntityId,
                              createdOn: selectedDate,
                              endOn: hasEffectiveRange ? selectedEndDate : null,
                              updatedOn: DateTime.now(),
                            );
                            if (widget.transaction == null) {
                              await state.addTransaction(tx);
                            } else if (isLoanTransaction) {
                              await state.updateLinkedLoanTransaction(tx);
                            } else {
                              await state.updateTransaction(tx);
                            }
                            if (context.mounted) {
                              showSnack(context, widget.transaction == null ? 'Transaction added.' : 'Transaction updated.');
                              Navigator.pop(context);
                            }
                          } catch (error) {
                            if (context.mounted) {
                              showSnack(context, 'Could not save transaction. ${error.toString().replaceFirst('Bad state: ', '').replaceFirst('Exception: ', '')}');
                            }
                          } finally {
                            if (mounted) setState(() => busy = false);
                          }
                        },
                  child: busy ? const KoinlyInlineLoader(size: 18, color: Colors.white) : const Text('Save'),
                ),
              ),
            ]),
          ],
        ),
      ),
    );
  }
}

Future<void> showDateRangeSheet(BuildContext context) async {
  final state = context.read<AppController>();
  final selectedId = await showAppleWheelSelectionSheet(
    context,
    title: 'Choose Date Filter',
    selectedId: enumName(state.dateRangeType),
    options: DateRangeType.values.map(optionFromDateRangeType).toList(),
  );
  if (selectedId == null) return;
  final selected = DateRangeType.values.firstWhere(
    (type) => enumName(type) == selectedId,
    orElse: () => state.dateRangeType,
  );

  if (selected == DateRangeType.custom) {
    final start = await pickDate(context, state.customStart ?? DateTime.now());
    if (!context.mounted || start == null) return;
    final end = await pickDate(context, state.customEnd ?? start);
    await state.setDateRange(selected, start: start, end: end ?? start);
    return;
  }

  await state.setDateRange(selected);
}

SelectionOption optionFromDateRangeType(DateRangeType type) {
  switch (type) {
    case DateRangeType.today:
      return const SelectionOption(
        id: 'today',
        title: 'Today',
        subtitle: 'Only today',
        iconName: 'today',
        iconColor: kSleekAccentHex,
      );
    case DateRangeType.thisWeek:
      return const SelectionOption(
        id: 'thisWeek',
        title: 'This Week',
        subtitle: 'Current week',
        iconName: 'week',
        iconColor: '#A6E3A1',
      );
    case DateRangeType.thisMonth:
      return const SelectionOption(
        id: 'thisMonth',
        title: 'This Month',
        subtitle: 'Current month',
        iconName: 'month',
        iconColor: kSleekAccentHex,
      );
    case DateRangeType.thisYear:
      return const SelectionOption(
        id: 'thisYear',
        title: 'This Year',
        subtitle: 'Current year',
        iconName: 'year',
        iconColor: '#FBC879',
      );
    case DateRangeType.allTime:
      return const SelectionOption(
        id: 'allTime',
        title: 'All Time',
        subtitle: 'Everything saved',
        iconName: 'all_time',
        iconColor: '#B4A5FF',
      );
    case DateRangeType.custom:
      return const SelectionOption(
        id: 'custom',
        title: 'Custom',
        subtitle: 'Choose start and end date',
        iconName: 'custom_range',
        iconColor: '#FFB5D0',
      );
  }
}

Future<void> showFilterSheet(BuildContext context) async {
  await showKoinlyPopup<void>(
    context,
    maxWidth: 560,
    maxHeight: 700,
    child: const FilterSheet(),
  );
}

class FilterSheet extends StatefulWidget {
  const FilterSheet({super.key});

  @override
  State<FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<FilterSheet> {
  late List<String> accounts;
  late List<String> categories;
  late List<MoneyTransactionType> types;

  @override
  void initState() {
    super.initState();
    final state = context.read<AppController>();
    accounts = List.of(state.filterAccountIds);
    categories = List.of(state.filterCategoryIds);
    types = List.of(state.filterTypes);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppController>();
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 18, 14, 14),
      child: KoinlyPopupContent(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Filters', textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900)),
            const SectionHeader('Accounts'),
            Wrap(spacing: 8, runSpacing: 8, children: state.accounts.map((a) => FilterChip(label: Text(a.name), selected: accounts.contains(a.id), onSelected: (v) => setState(() => v ? accounts.add(a.id) : accounts.remove(a.id)))).toList()),
            const SectionHeader('Categories'),
            Wrap(spacing: 8, runSpacing: 8, children: state.categories.map((c) => FilterChip(label: Text(c.name), selected: categories.contains(c.id), onSelected: (v) => setState(() => v ? categories.add(c.id) : categories.remove(c.id)))).toList()),
            const SectionHeader('Types'),
            Wrap(spacing: 8, runSpacing: 8, children: MoneyTransactionType.values.map((t) => FilterChip(label: Text(enumName(t)), selected: types.contains(t), onSelected: (v) => setState(() => v ? types.add(t) : types.remove(t)))).toList()),
            const SizedBox(height: 18),
            Row(children: [
              Expanded(child: OutlinedButton(onPressed: () async { await state.clearFilters(); if (context.mounted) Navigator.pop(context); }, child: const Text('Clear'))),
              const SizedBox(width: 12),
              Expanded(flex: 2, child: FilledButton(onPressed: () async { await state.saveFilters(accounts: accounts, categories: categories, types: types); if (context.mounted) Navigator.pop(context); }, child: const Text('Apply'))),
            ]),
          ],
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Analysis and category breakdown
// -----------------------------------------------------------------------------

class AnalysisScreen extends StatefulWidget {
  const AnalysisScreen({super.key});

  @override
  State<AnalysisScreen> createState() => _AnalysisScreenState();
}

class _AnalysisScreenState extends State<AnalysisScreen> {
  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppController>();
    final range = state.activeRange();
    final txs = state.filteredTransactions();
    final summary = state.summaryFor(txs);
    final fallbackToday = DateTime.now();
    final fallbackDay = DateTime(fallbackToday.year, fallbackToday.month, fallbackToday.day);
    DateTime chartStart;
    DateTime chartEnd;
    if (range.start != null && range.end != null) {
      chartStart = range.start!;
      chartEnd = range.end!;
    } else if (txs.isNotEmpty) {
      var first = txs.first.createdOn;
      var last = txs.first.createdOn;
      for (final tx in txs.skip(1)) {
        if (tx.createdOn.isBefore(first)) first = tx.createdOn;
        if (tx.createdOn.isAfter(last)) last = tx.createdOn;
      }
      chartStart = DateTime(first.year, first.month, first.day);
      chartEnd = DateTime(last.year, last.month, last.day).add(const Duration(days: 1));
    } else {
      chartStart = fallbackDay;
      chartEnd = fallbackDay.add(const Duration(days: 1));
    }
    final daily = <DateTime, Summary>{};
    for (final tx in txs) {
      if (!tx.countsAsIncome && !tx.countsAsExpense) continue;
      final day = DateTime(tx.createdOn.year, tx.createdOn.month, tx.createdOn.day);
      final old = daily[day] ?? const Summary(income: 0, expense: 0);
      daily[day] = Summary(
        income: old.income + (tx.countsAsIncome ? tx.amount : 0),
        expense: old.expense + (tx.countsAsExpense ? tx.amount : 0),
      );
    }

    final totalDays = chartEnd.difference(chartStart).inDays;
    List<DateTime> days;
    if (totalDays > 0 && totalDays <= 62) {
      days = List.generate(totalDays, (index) => DateTime(chartStart.year, chartStart.month, chartStart.day).add(Duration(days: index)));
    } else if (daily.isNotEmpty) {
      days = daily.keys.toList()..sort();
    } else {
      days = [DateTime(chartStart.year, chartStart.month, chartStart.day)];
    }
    for (final day in days) {
      daily.putIfAbsent(day, () => const Summary(income: 0, expense: 0));
    }
    final avgDivisor = math.max(1, days.length);

    return PageScaffold(
      title: 'Analysis',
      subtitle: range.label,
      actions: [IconButton(onPressed: () => showFilterSheet(context), icon: const Icon(Icons.filter_alt_rounded))],
      child: ResponsiveContent(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              Expanded(child: MiniMetric('Income', state.format(summary.income), Icons.south_west_rounded)),
              const SizedBox(width: 10),
              Expanded(child: MiniMetric('Expense', state.format(summary.expense), Icons.north_east_rounded)),
            ]),
            const SizedBox(height: 10),
            MiniMetric('Balance', state.format(summary.balance), Icons.account_balance_wallet_rounded),
            const SectionHeader('Cash flow'),
            RepaintBoundary(child: AnalysisTrendChart(days: days, daily: daily, rangeLabel: range.label)),
            const SectionHeader('Averages'),
            Row(children: [
              Expanded(child: MiniMetric('Income / day', state.format(summary.income / avgDivisor), Icons.trending_up_rounded)),
              const SizedBox(width: 10),
              Expanded(child: MiniMetric('Expense / day', state.format(summary.expense / avgDivisor), Icons.trending_down_rounded)),
            ]),
          ],
        ),
      ),
    );
  }
}

DateTime financialPeriodStart(FinancialHealthPeriod period, DateTime selectedDate) {
  return period == FinancialHealthPeriod.monthly ? DateTime(selectedDate.year, selectedDate.month, 1) : DateTime(selectedDate.year, 1, 1);
}

DateTime financialPeriodEnd(FinancialHealthPeriod period, DateTime selectedDate) {
  return period == FinancialHealthPeriod.monthly ? DateTime(selectedDate.year, selectedDate.month + 1, 1) : DateTime(selectedDate.year + 1, 1, 1);
}

String financialPeriodLabel(FinancialHealthPeriod period, DateTime selectedDate) {
  return period == FinancialHealthPeriod.monthly ? DateFormat('MMMM yyyy').format(selectedDate) : selectedDate.year.toString();
}

List<SelectionOption> financialMonthOptions() {
  final now = DateTime.now();
  return List.generate(144, (index) {
    final month = DateTime(now.year, now.month - index, 1);
    return SelectionOption(
      id: DateFormat('yyyy-MM').format(month),
      title: DateFormat('MMMM yyyy').format(month),
      subtitle: index == 0 ? 'Current month' : 'Monthly health summary',
      iconName: 'month',
      iconColor: kSleekAccentHex,
    );
  });
}

List<SelectionOption> financialYearOptions() {
  final now = DateTime.now();
  final count = math.max(1, now.year - 1999);
  return List.generate(count, (index) {
    final year = now.year - index;
    return SelectionOption(
      id: year.toString(),
      title: year.toString(),
      subtitle: index == 0 ? 'Current year' : 'Yearly health summary',
      iconName: 'year',
      iconColor: '#FBC879',
    );
  });
}

bool isInsideFinancialPeriod(DateTime date, DateTime start, DateTime end) => !date.isBefore(start) && date.isBefore(end);

List<MoneyTransaction> transactionsForFinancialPeriod(AppController state, DateTime start, DateTime end) {
  return state.transactions.where((tx) => isInsideFinancialPeriod(tx.createdOn, start, end)).toList();
}

bool transactionTouchesSavings(AppController state, MoneyTransaction tx) {
  final from = state.accountOf(tx.fromAccountId);
  final to = tx.toAccountId == null ? null : state.accountOf(tx.toAccountId!);
  return from?.type == AccountType.savings || to?.type == AccountType.savings;
}

bool isSavingsTransferIn(AppController state, MoneyTransaction tx) {
  if (tx.type != MoneyTransactionType.transfer) return false;
  final from = state.accountOf(tx.fromAccountId);
  final to = tx.toAccountId == null ? null : state.accountOf(tx.toAccountId!);
  return from?.type != AccountType.savings && to?.type == AccountType.savings;
}

bool isSavingsTransferOut(AppController state, MoneyTransaction tx) {
  if (tx.type != MoneyTransactionType.transfer) return false;
  final from = state.accountOf(tx.fromAccountId);
  final to = tx.toAccountId == null ? null : state.accountOf(tx.toAccountId!);
  return from?.type == AccountType.savings && to?.type != AccountType.savings;
}

bool isRecurringPaymentTransaction(AppController state, MoneyTransaction tx) {
  if (!tx.countsAsExpense) return false;
  final category = state.categoryOf(tx.categoryId)?.name.toLowerCase() ?? '';
  final title = tx.title.toLowerCase();
  final notes = tx.notes.toLowerCase();
  final text = '$title $category $notes';
  const keywords = [
    'bill',
    'subscription',
    'tuition',
    'rent',
    'internet',
    'mobile recharge',
    'recharge',
    'electricity',
    'utility',
    'school fee',
    'fee',
    'netflix',
    'spotify',
    'youtube',
  ];
  return keywords.any(text.contains);
}

class BudgetThresholdCounts {
  const BudgetThresholdCounts({required this.safe, required this.fifty, required this.eighty, required this.full, required this.over});

  final int safe;
  final int fifty;
  final int eighty;
  final int full;
  final int over;
}

class BudgetHealthItem {
  const BudgetHealthItem({required this.label, required this.month, required this.limit, required this.spent});

  final String label;
  final DateTime month;
  final double limit;
  final double spent;

  double get remaining => limit - spent;
  double get overspent => math.max(0, spent - limit);
  double get ratio => limit <= 0 ? 0 : spent / limit;
  double get percentUsed => ratio * 100;
  bool get isOverspent => spent > limit && limit > 0;

  String get statusLabel {
    if (ratio >= 1.0001) return 'Over Budget';
    if (ratio >= .999) return 'Fully Used';
    if (ratio >= .8) return 'Near Limit';
    if (ratio >= .5) return '50% Used';
    return 'Safe';
  }
}

class MonthlyFinancialBreakdown {
  const MonthlyFinancialBreakdown({
    required this.month,
    required this.income,
    required this.expense,
    required this.savingsIn,
    required this.savingsOut,
    required this.billPaymentTotal,
    required this.billPaymentCount,
    required this.budgetLimit,
    required this.budgetSpent,
  });

  final DateTime month;
  final double income;
  final double expense;
  final double savingsIn;
  final double savingsOut;
  final double billPaymentTotal;
  final int billPaymentCount;
  final double budgetLimit;
  final double budgetSpent;

  double get cashFlow => income - expense;
  double get savingsNet => savingsIn - savingsOut;
  double get budgetRemaining => budgetLimit - budgetSpent;
  double get overspent => math.max(0, budgetSpent - budgetLimit);
}

class FinancialHealthSummary {
  const FinancialHealthSummary({
    required this.state,
    required this.period,
    required this.selectedDate,
    required this.start,
    required this.end,
    required this.periodLabel,
    required this.income,
    required this.expense,
    required this.savingsIn,
    required this.savingsOut,
    required this.currentSavingsBalance,
    required this.billPaymentTotal,
    required this.billPaymentCount,
    required this.billUnpaidCount,
    required this.billUpcomingCount,
    required this.billOverdueCount,
    required this.budgetItems,
    required this.budgetCounts,
    required this.monthlyBreakdowns,
    required this.status,
    required this.statusBody,
  });

  final AppController state;
  final FinancialHealthPeriod period;
  final DateTime selectedDate;
  final DateTime start;
  final DateTime end;
  final String periodLabel;
  final double income;
  final double expense;
  final double savingsIn;
  final double savingsOut;
  final double currentSavingsBalance;
  final double billPaymentTotal;
  final int billPaymentCount;
  final int billUnpaidCount;
  final int billUpcomingCount;
  final int billOverdueCount;
  final List<BudgetHealthItem> budgetItems;
  final BudgetThresholdCounts budgetCounts;
  final List<MonthlyFinancialBreakdown> monthlyBreakdowns;
  final String status;
  final String statusBody;

  double get cashFlow => income - expense;
  double get savingsNet => savingsIn - savingsOut;
  double get budgetLimit => budgetItems.fold<double>(0, (sum, item) => sum + item.limit);
  double get budgetSpent => budgetItems.fold<double>(0, (sum, item) => sum + item.spent);
  double get budgetRemaining => budgetLimit - budgetSpent;
  double get overspentTotal => budgetItems.fold<double>(0, (sum, item) => sum + item.overspent);
  List<BudgetHealthItem> get overspentItems => budgetItems.where((item) => item.isOverspent).toList();

  static FinancialHealthSummary build(AppController state, {required FinancialHealthPeriod period, required DateTime selectedDate}) {
    final start = financialPeriodStart(period, selectedDate);
    final end = financialPeriodEnd(period, selectedDate);
    final txs = transactionsForFinancialPeriod(state, start, end);
    double income = 0;
    double expense = 0;
    double savingsIn = 0;
    double savingsOut = 0;
    double billPaymentTotal = 0;
    var billPaymentCount = 0;

    for (final tx in txs) {
      if (tx.countsAsIncome) income += tx.amount;
      if (tx.countsAsExpense) expense += tx.amount;
      if (isSavingsTransferIn(state, tx)) savingsIn += tx.amount;
      if (isSavingsTransferOut(state, tx)) savingsOut += tx.amount;
      if (isRecurringPaymentTransaction(state, tx)) {
        billPaymentTotal += tx.amount;
        billPaymentCount++;
      }
    }

    final budgetItems = budgetHealthItemsForPeriod(state, period, selectedDate);
    var safe = 0;
    var fifty = 0;
    var eighty = 0;
    var full = 0;
    var over = 0;
    for (final item in budgetItems) {
      if (item.ratio >= 1.0001) {
        over++;
      } else if (item.ratio >= .999) {
        full++;
      } else if (item.ratio >= .8) {
        eighty++;
      } else if (item.ratio >= .5) {
        fifty++;
      } else {
        safe++;
      }
    }

    final monthlyBreakdowns = period == FinancialHealthPeriod.yearly
        ? List.generate(12, (index) => monthlyBreakdownFor(state, DateTime(selectedDate.year, index + 1, 1)))
        : <MonthlyFinancialBreakdown>[];

    final statusInfo = financialHealthStatus(
      period: period,
      income: income,
      expense: expense,
      savingsNet: savingsIn - savingsOut,
      overspentTotal: budgetItems.fold<double>(0, (sum, item) => sum + item.overspent),
    );

    return FinancialHealthSummary(
      state: state,
      period: period,
      selectedDate: selectedDate,
      start: start,
      end: end,
      periodLabel: financialPeriodLabel(period, selectedDate),
      income: income,
      expense: expense,
      savingsIn: savingsIn,
      savingsOut: savingsOut,
      currentSavingsBalance: state.savingAccountBalance,
      billPaymentTotal: billPaymentTotal,
      billPaymentCount: billPaymentCount,
      billUnpaidCount: 0,
      billUpcomingCount: 0,
      billOverdueCount: 0,
      budgetItems: budgetItems,
      budgetCounts: BudgetThresholdCounts(safe: safe, fifty: fifty, eighty: eighty, full: full, over: over),
      monthlyBreakdowns: monthlyBreakdowns,
      status: statusInfo.$1,
      statusBody: statusInfo.$2,
    );
  }
}

(String, String) financialHealthStatus({
  required FinancialHealthPeriod period,
  required double income,
  required double expense,
  required double savingsNet,
  required double overspentTotal,
}) {
  final label = period == FinancialHealthPeriod.monthly ? 'month' : 'year';
  if (overspentTotal > 0 || expense > income) {
    return ('Overspent', 'Expenses or budget usage were higher than the safe limit in this $label.');
  }
  if (savingsNet > math.max(100, income * .18)) {
    return ('Strong Savings Growth', 'Savings transfers were strong compared with income in this $label.');
  }
  if (income > expense) {
    return ('Saved Money', 'Income stayed above expenses in this $label.');
  }
  return ('Stable ${period == FinancialHealthPeriod.monthly ? 'Month' : 'Year'}', 'Money flow stayed close to neutral in this $label.');
}

List<BudgetHealthItem> budgetHealthItemsForPeriod(AppController state, FinancialHealthPeriod period, DateTime selectedDate) {
  final items = <BudgetHealthItem>[];
  for (final budget in state.budgets) {
    final month = DateTime(budget.selectedMonth.year, budget.selectedMonth.month, 1);
    if (period == FinancialHealthPeriod.monthly) {
      if (month.year != selectedDate.year || month.month != selectedDate.month) continue;
    } else if (month.year != selectedDate.year) {
      continue;
    }
    final start = DateTime(month.year, month.month, 1);
    final end = DateTime(month.year, month.month + 1, 1);
    final txs = state.transactions.where((tx) {
      if (!tx.countsAsExpense) return false;
      if (!isInsideFinancialPeriod(tx.createdOn, start, end)) return false;
      if (!budget.allAccountsSelected && !budget.accountIds.contains(tx.fromAccountId)) return false;
      if (!budget.allCategoriesSelected && !budget.categoryIds.contains(tx.categoryId)) return false;
      return true;
    }).toList();
    final spent = txs.fold<double>(0, (sum, tx) => sum + tx.amount);
    final categoryNames = budget.allCategoriesSelected
        ? 'All expense categories'
        : budget.categoryIds.map((id) => state.categoryOf(id)?.name ?? 'Category').take(3).join(', ');
    final accountNames = budget.allAccountsSelected ? 'all accounts' : budget.accountIds.map((id) => state.accountOf(id)?.name ?? 'Account').take(2).join(', ');
    final label = period == FinancialHealthPeriod.yearly ? '${DateFormat('MMM').format(month)} • $categoryNames' : '$categoryNames • $accountNames';
    items.add(BudgetHealthItem(label: label, month: month, limit: budget.amount, spent: spent));
  }
  return items;
}

MonthlyFinancialBreakdown monthlyBreakdownFor(AppController state, DateTime month) {
  final start = DateTime(month.year, month.month, 1);
  final end = DateTime(month.year, month.month + 1, 1);
  final txs = transactionsForFinancialPeriod(state, start, end);
  double income = 0;
  double expense = 0;
  double savingsIn = 0;
  double savingsOut = 0;
  double billPaymentTotal = 0;
  var billPaymentCount = 0;
  for (final tx in txs) {
    if (tx.countsAsIncome) income += tx.amount;
    if (tx.countsAsExpense) expense += tx.amount;
    if (isSavingsTransferIn(state, tx)) savingsIn += tx.amount;
    if (isSavingsTransferOut(state, tx)) savingsOut += tx.amount;
    if (isRecurringPaymentTransaction(state, tx)) {
      billPaymentTotal += tx.amount;
      billPaymentCount++;
    }
  }
  final budgetItems = budgetHealthItemsForPeriod(state, FinancialHealthPeriod.monthly, month);
  return MonthlyFinancialBreakdown(
    month: month,
    income: income,
    expense: expense,
    savingsIn: savingsIn,
    savingsOut: savingsOut,
    billPaymentTotal: billPaymentTotal,
    billPaymentCount: billPaymentCount,
    budgetLimit: budgetItems.fold<double>(0, (sum, item) => sum + item.limit),
    budgetSpent: budgetItems.fold<double>(0, (sum, item) => sum + item.spent),
  );
}

class FinancialHealthPeriodCard extends StatelessWidget {
  const FinancialHealthPeriodCard({super.key, required this.period, required this.selectedDate, required this.onPeriodChanged, required this.onPickDate});

  final FinancialHealthPeriod period;
  final DateTime selectedDate;
  final ValueChanged<FinancialHealthPeriod> onPeriodChanged;
  final VoidCallback onPickDate;

  @override
  Widget build(BuildContext context) {
    final selectedLabel = financialPeriodLabel(period, selectedDate);
    return ExpressiveCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SegmentedButton<FinancialHealthPeriod>(
            segments: const [
              ButtonSegment(value: FinancialHealthPeriod.monthly, label: Text('Monthly'), icon: Icon(Icons.calendar_month_rounded)),
              ButtonSegment(value: FinancialHealthPeriod.yearly, label: Text('Yearly'), icon: Icon(Icons.calendar_view_month_rounded)),
            ],
            selected: {period},
            onSelectionChanged: (value) => onPeriodChanged(value.first),
            showSelectedIcon: false,
          ),
          const SizedBox(height: 12),
          Material(
            color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(.48),
            borderRadius: BorderRadius.circular(18),
            child: MotionInkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: onPickDate,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Row(
                  children: [
                    iconBubble(context, period == FinancialHealthPeriod.monthly ? 'month' : 'year', period == FinancialHealthPeriod.monthly ? kSleekAccentHex : '#FBC879', size: 42),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(selectedLabel, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
                          Text(period == FinancialHealthPeriod.monthly ? 'Tap to choose another month' : 'Tap to choose another year', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: kSleekMuted, fontWeight: FontWeight.w700)),
                        ],
                      ),
                    ),
                    Icon(Icons.keyboard_arrow_down_rounded, color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class FinancialHealthSummarySection extends StatelessWidget {
  const FinancialHealthSummarySection({super.key, required this.summary});

  final FinancialHealthSummary summary;

  @override
  Widget build(BuildContext context) {
    final state = summary.state;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader('Financial Health Summary'),
        FinancialHealthStatusCard(summary: summary),
        const SizedBox(height: 10),
        HealthMetricWrap(metrics: [
          HealthMetricData('Money flow', state.format(summary.cashFlow), Icons.compare_arrows_rounded),
          HealthMetricData('Savings in', state.format(summary.savingsIn), Icons.savings_rounded),
          HealthMetricData('Savings out', state.format(summary.savingsOut), Icons.output_rounded),
          HealthMetricData('Savings change', state.format(summary.savingsNet), Icons.trending_up_rounded),
          HealthMetricData('Current savings', state.format(summary.currentSavingsBalance), Icons.account_balance_rounded),
          HealthMetricData('Recurring paid', state.format(summary.billPaymentTotal), Icons.receipt_long_rounded),
          HealthMetricData('Budget remaining', state.format(summary.budgetRemaining), Icons.pie_chart_rounded),
          HealthMetricData('Overspent', state.format(summary.overspentTotal), Icons.warning_rounded),
        ]),
        const SizedBox(height: 10),
        FinancialHealthCharts(summary: summary),
        const SizedBox(height: 10),
        BudgetHealthCard(summary: summary),
        const SizedBox(height: 10),
        BillStatusCard(summary: summary),
        if (summary.overspentItems.isNotEmpty) ...[
          const SizedBox(height: 10),
          OverspendingCategoriesCard(summary: summary),
        ],
        if (summary.period == FinancialHealthPeriod.yearly) ...[
          const SizedBox(height: 10),
          YearlyComparisonCard(summary: summary),
          const SizedBox(height: 10),
          YearlyBreakdownCard(summary: summary),
        ],
      ],
    );
  }
}

class FinancialHealthStatusCard extends StatelessWidget {
  const FinancialHealthStatusCard({super.key, required this.summary});

  final FinancialHealthSummary summary;

  Color _statusColor() {
    final lower = summary.status.toLowerCase();
    if (lower.contains('over')) return kSleekExpense;
    if (lower.contains('strong') || lower.contains('saved') || lower.contains('reduced')) return kSleekIncome;
    return kSleekAccent;
  }

  @override
  Widget build(BuildContext context) {
    final color = _statusColor();
    return ExpressiveCard(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(color: color.withOpacity(.15), borderRadius: BorderRadius.circular(18), border: Border.all(color: color.withOpacity(.30))),
            child: Icon(Icons.health_and_safety_rounded, color: color),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(summary.status, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
                    HealthStatusPill(label: summary.periodLabel, color: color),
                    const HealthStatusPill(label: 'Savings transfers are internal', color: kSleekAccent),
                  ],
                ),
                const SizedBox(height: 6),
                Text(summary.statusBody, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: kSleekMuted, fontWeight: FontWeight.w700)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class HealthStatusPill extends StatelessWidget {
  const HealthStatusPill({super.key, required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: color.withOpacity(.12), borderRadius: BorderRadius.circular(999), border: Border.all(color: color.withOpacity(.24))),
      child: Text(label, style: Theme.of(context).textTheme.labelMedium?.copyWith(color: color, fontWeight: FontWeight.w900)),
    );
  }
}

class HealthMetricData {
  const HealthMetricData(this.label, this.value, this.icon);
  final String label;
  final String value;
  final IconData icon;
}

class HealthMetricWrap extends StatelessWidget {
  const HealthMetricWrap({super.key, required this.metrics});

  final List<HealthMetricData> metrics;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final twoColumns = constraints.maxWidth >= 680;
        final width = twoColumns ? (constraints.maxWidth - 10) / 2 : constraints.maxWidth;
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: metrics.map((metric) => SizedBox(width: width, child: MiniMetric(metric.label, metric.value, metric.icon))).toList(),
        );
      },
    );
  }
}

class FinancialHealthCharts extends StatelessWidget {
  const FinancialHealthCharts({super.key, required this.summary});

  final FinancialHealthSummary summary;

  @override
  Widget build(BuildContext context) {
    final state = summary.state;
    final budgetRemaining = math.max(0.0, summary.budgetRemaining);
    return LayoutBuilder(
      builder: (context, constraints) {
        final twoColumns = constraints.maxWidth >= 760;
        final width = twoColumns ? (constraints.maxWidth - 10) / 2 : constraints.maxWidth;
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            SizedBox(
              width: width,
              child: HealthBarChartCard(
                title: 'Income vs Expense',
                icon: Icons.stacked_bar_chart_rounded,
                bars: [
                  HealthBarData('Income', summary.income, state.format(summary.income), kSleekIncome),
                  HealthBarData('Expense', summary.expense, state.format(summary.expense), kSleekExpense),
                ],
              ),
            ),
            SizedBox(
              width: width,
              child: HealthBarChartCard(
                title: 'Savings Growth',
                icon: Icons.savings_rounded,
                bars: [
                  HealthBarData('Transferred in', summary.savingsIn, state.format(summary.savingsIn), kSleekIncome),
                  HealthBarData('Transferred out', summary.savingsOut, state.format(summary.savingsOut), kSleekExpense),
                  HealthBarData('Net change', summary.savingsNet.abs(), state.format(summary.savingsNet), summary.savingsNet >= 0 ? kSleekIncome : kSleekExpense),
                ],
              ),
            ),
            SizedBox(
              width: width,
              child: HealthBarChartCard(
                title: 'Budget Usage',
                icon: Icons.pie_chart_rounded,
                bars: [
                  HealthBarData('Used', summary.budgetSpent, state.format(summary.budgetSpent), kSleekWarning),
                  HealthBarData('Remaining', budgetRemaining, state.format(summary.budgetRemaining), kSleekIncome),
                  HealthBarData('Overspent', summary.overspentTotal, state.format(summary.overspentTotal), kSleekExpense),
                ],
              ),
            ),
            SizedBox(
              width: width,
              child: HealthBarChartCard(
                title: 'Recurring Payments',
                icon: Icons.repeat_rounded,
                bars: [
                  HealthBarData('Paid bills', summary.billPaymentTotal, state.format(summary.billPaymentTotal), kSleekAccent),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class HealthBarData {
  const HealthBarData(this.label, this.value, this.displayValue, this.color);
  final String label;
  final double value;
  final String displayValue;
  final Color color;
}

class HealthBarChartCard extends StatelessWidget {
  const HealthBarChartCard({super.key, required this.title, required this.icon, required this.bars});

  final String title;
  final IconData icon;
  final List<HealthBarData> bars;

  @override
  Widget build(BuildContext context) {
    final maxValue = bars.fold<double>(0, (max, bar) => math.max(max, bar.value.abs()));
    return ExpressiveCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: kSleekAccent),
              const SizedBox(width: 8),
              Expanded(child: Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900))),
            ],
          ),
          const SizedBox(height: 14),
          ...bars.map((bar) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: HealthBarRow(data: bar, maxValue: maxValue),
              )),
        ],
      ),
    );
  }
}

class HealthBarRow extends StatelessWidget {
  const HealthBarRow({super.key, required this.data, required this.maxValue});

  final HealthBarData data;
  final double maxValue;

  @override
  Widget build(BuildContext context) {
    final factor = maxValue <= 0 ? 0.0 : (data.value.abs() / maxValue).clamp(0.0, 1.0).toDouble();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: Text(data.label, style: Theme.of(context).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800))),
            const SizedBox(width: 8),
            Text(data.displayValue, style: Theme.of(context).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w900)),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: Container(
            height: 10,
            color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(.58),
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: factor,
              child: Container(decoration: BoxDecoration(color: data.color, borderRadius: BorderRadius.circular(999))),
            ),
          ),
        ),
      ],
    );
  }
}

class BudgetHealthCard extends StatelessWidget {
  const BudgetHealthCard({super.key, required this.summary});

  final FinancialHealthSummary summary;

  @override
  Widget build(BuildContext context) {
    final state = summary.state;
    final counts = summary.budgetCounts;
    return ExpressiveCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Budget status', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              HealthStatusPill(label: 'Safe ${counts.safe}', color: kSleekIncome),
              HealthStatusPill(label: '50% ${counts.fifty}', color: kSleekAccent),
              HealthStatusPill(label: '80% ${counts.eighty}', color: kSleekWarning),
              HealthStatusPill(label: '100% ${counts.full}', color: const Color(0xFFFFB86B)),
              HealthStatusPill(label: 'Over ${counts.over}', color: kSleekExpense),
            ],
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: MiniMetric('Budget limit', state.format(summary.budgetLimit), Icons.flag_rounded)),
            const SizedBox(width: 10),
            Expanded(child: MiniMetric('Remaining budget', state.format(summary.budgetRemaining), Icons.savings_rounded)),
          ]),
        ],
      ),
    );
  }
}

class BillStatusCard extends StatelessWidget {
  const BillStatusCard({super.key, required this.summary});

  final FinancialHealthSummary summary;

  @override
  Widget build(BuildContext context) {
    return ExpressiveCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Reminders and scheduled payments', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              HealthStatusPill(label: 'Bills paid ${summary.billPaymentCount}', color: kSleekAccent),
              HealthStatusPill(label: 'Bills unpaid ${summary.billUnpaidCount}', color: kSleekWarning),
              HealthStatusPill(label: 'Bills upcoming ${summary.billUpcomingCount}', color: const Color(0xFF8AB4FF)),
              HealthStatusPill(label: 'Bills overdue ${summary.billOverdueCount}', color: kSleekExpense),
            ],
          ),
        ],
      ),
    );
  }
}

class OverspendingCategoriesCard extends StatelessWidget {
  const OverspendingCategoriesCard({super.key, required this.summary});

  final FinancialHealthSummary summary;

  @override
  Widget build(BuildContext context) {
    final state = summary.state;
    return ExpressiveCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Overspending categories', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          ...summary.overspentItems.map((item) => Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: kSleekExpense.withOpacity(.08),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: kSleekExpense.withOpacity(.18)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(child: Text(item.label, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900))),
                          Text('${item.percentUsed.toStringAsFixed(0)}%', style: Theme.of(context).textTheme.titleSmall?.copyWith(color: kSleekExpense, fontWeight: FontWeight.w900)),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text('Spent ${state.format(item.spent)} • Limit ${state.format(item.limit)} • Overspent ${state.format(item.overspent)}', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: kSleekMuted, fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
              )),
        ],
      ),
    );
  }
}

class YearlyComparisonCard extends StatelessWidget {
  const YearlyComparisonCard({super.key, required this.summary});

  final FinancialHealthSummary summary;

  MonthlyFinancialBreakdown? _maxBy(double Function(MonthlyFinancialBreakdown item) selector) {
    if (summary.monthlyBreakdowns.isEmpty) return null;
    return summary.monthlyBreakdowns.reduce((a, b) => selector(a) >= selector(b) ? a : b);
  }

  MonthlyFinancialBreakdown? _minBy(double Function(MonthlyFinancialBreakdown item) selector) {
    if (summary.monthlyBreakdowns.isEmpty) return null;
    return summary.monthlyBreakdowns.reduce((a, b) => selector(a) <= selector(b) ? a : b);
  }

  String _month(MonthlyFinancialBreakdown? item) => item == null ? '-' : DateFormat('MMM').format(item.month);

  @override
  Widget build(BuildContext context) {
    final best = _maxBy((item) => item.cashFlow);
    final worst = _minBy((item) => item.cashFlow);
    final highestExpense = _maxBy((item) => item.expense);
    final highestIncome = _maxBy((item) => item.income);
    final highestSavings = _maxBy((item) => item.savingsNet);
    final mostOverspent = _maxBy((item) => item.overspent);
    return ExpressiveCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Monthly comparison', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              HealthStatusPill(label: 'Best ${_month(best)}', color: kSleekIncome),
              HealthStatusPill(label: 'Worst ${_month(worst)}', color: kSleekExpense),
              HealthStatusPill(label: 'Highest expense ${_month(highestExpense)}', color: kSleekWarning),
              HealthStatusPill(label: 'Highest income ${_month(highestIncome)}', color: kSleekIncome),
              HealthStatusPill(label: 'Highest savings ${_month(highestSavings)}', color: kSleekAccent),
              HealthStatusPill(label: 'Most overspent ${_month(mostOverspent)}', color: kSleekExpense),
            ],
          ),
        ],
      ),
    );
  }
}

class YearlyBreakdownCard extends StatelessWidget {
  const YearlyBreakdownCard({super.key, required this.summary});

  final FinancialHealthSummary summary;

  @override
  Widget build(BuildContext context) {
    final state = summary.state;
    final maxExpense = summary.monthlyBreakdowns.fold<double>(0, (max, item) => math.max(max, item.expense));
    return ExpressiveCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Yearly breakdown', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
          const SizedBox(height: 10),
          ...summary.monthlyBreakdowns.map((item) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: MonthBreakdownTile(item: item, maxExpense: maxExpense, state: state),
              )),
        ],
      ),
    );
  }
}

class MonthBreakdownTile extends StatelessWidget {
  const MonthBreakdownTile({super.key, required this.item, required this.maxExpense, required this.state});

  final MonthlyFinancialBreakdown item;
  final double maxExpense;
  final AppController state;

  @override
  Widget build(BuildContext context) {
    final factor = maxExpense <= 0 ? 0.0 : (item.expense / maxExpense).clamp(0.0, 1.0).toDouble();
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(.42),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Theme.of(context).colorScheme.outline.withOpacity(.16)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              SizedBox(width: 44, child: Text(DateFormat('MMM').format(item.month), style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900))),
              Expanded(child: Text('Income ${state.format(item.income)} • Expense ${state.format(item.expense)}', maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: kSleekMuted, fontWeight: FontWeight.w700))),
              Text(state.format(item.cashFlow), style: Theme.of(context).textTheme.labelLarge?.copyWith(color: item.cashFlow >= 0 ? kSleekIncome : kSleekExpense, fontWeight: FontWeight.w900)),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: Container(
              height: 9,
              color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(.70),
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(widthFactor: factor, child: Container(color: kSleekExpense)),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Savings ${state.format(item.savingsNet)} • Bills ${item.billPaymentCount} • Budget used ${state.format(item.budgetSpent)}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: kSleekMuted, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

enum _TrendView { both, income, expense }

class AnalysisTrendChart extends StatefulWidget {
  const AnalysisTrendChart({
    super.key,
    required this.days,
    required this.daily,
    required this.rangeLabel,
  });

  final List<DateTime> days;
  final Map<DateTime, Summary> daily;
  final String rangeLabel;

  @override
  State<AnalysisTrendChart> createState() => _AnalysisTrendChartState();
}

class _AnalysisTrendChartState extends State<AnalysisTrendChart> {
  _TrendView _view = _TrendView.both;

  List<FlSpot> _spotsFor(bool income) {
    if (widget.days.isEmpty) return const [FlSpot(0, 0), FlSpot(1, 0)];
    final spots = <FlSpot>[];
    for (var i = 0; i < widget.days.length; i++) {
      final summary = widget.daily[widget.days[i]] ?? const Summary(income: 0, expense: 0);
      spots.add(FlSpot(i.toDouble(), income ? summary.income : summary.expense));
    }
    if (spots.length == 1) spots.add(FlSpot(1, spots.first.y));
    return spots;
  }

  double _niceMaxY(Iterable<double> values) {
    final highest = values.fold<double>(0, (current, value) => math.max(current, value).toDouble());
    if (highest <= 0) return 100;
    final padded = highest * 1.18;
    final magnitude = math.pow(10, (math.log(padded) / math.ln10).floor()).toDouble();
    final normalized = padded / magnitude;
    final rounded = normalized <= 2
        ? 2
        : normalized <= 5
            ? 5
            : 10;
    return rounded * magnitude;
  }

  String _compactCurrency(AppController state, double value) {
    if (state.amountsHidden) {
      return state.currencyPosition == CurrencyPosition.prefix
          ? '${state.currencySymbol}••••'
          : '••••${state.currencySymbol}';
    }
    final absolute = value.abs();
    String number;
    if (absolute >= 1000000) {
      number = '${(absolute / 1000000).toStringAsFixed(absolute % 1000000 == 0 ? 0 : 1)}M';
    } else if (absolute >= 1000) {
      number = '${(absolute / 1000).toStringAsFixed(absolute % 1000 == 0 ? 0 : 1)}K';
    } else {
      number = absolute.toStringAsFixed(absolute % 1 == 0 ? 0 : 1);
    }
    final sign = value < 0 ? '-' : '';
    return state.currencyPosition == CurrencyPosition.prefix
        ? '$sign${state.currencySymbol}$number'
        : '$sign$number${state.currencySymbol}';
  }

  Set<int> _bottomLabelIndexes() {
    final count = widget.days.length;
    if (count <= 1) return {0};
    if (count <= 4) return {for (var i = 0; i < count; i++) i};
    return {
      0,
      ((count - 1) / 3).round(),
      (((count - 1) * 2) / 3).round(),
      count - 1,
    };
  }

  String _dateLabel(DateTime day) {
    if (widget.days.length <= 1) return DateFormat('MMM d').format(day);
    final first = widget.days.first;
    final last = widget.days.last;
    final span = last.difference(first).inDays.abs();
    if (span > 365) return DateFormat('MMM yy').format(day);
    if (span > 62) return DateFormat('MMM').format(day);
    return DateFormat('MMM d').format(day);
  }

  Widget _leftTitle(BuildContext context, double value, TitleMeta meta, double maxY) {
    final interval = maxY / 4;
    if (interval <= 0) return const SizedBox.shrink();
    final slot = (value / interval).round();
    if ((value - slot * interval).abs() > .01) return const SizedBox.shrink();
    final state = context.read<AppController>();
    return Text(
      _compactCurrency(state, value),
      maxLines: 1,
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(.76),
            fontWeight: FontWeight.w800,
          ),
    );
  }

  Widget _bottomTitle(BuildContext context, double value, TitleMeta meta) {
    if (widget.days.isEmpty) return const SizedBox.shrink();
    final index = value.round();
    if (index < 0 || index >= widget.days.length || !_bottomLabelIndexes().contains(index)) {
      return const SizedBox.shrink();
    }
    return SideTitleWidget(
      axisSide: meta.axisSide,
      space: 10,
      child: Text(
        _dateLabel(widget.days[index]),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant.withOpacity(.78),
              fontWeight: FontWeight.w800,
            ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppController>();
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final incomeSpots = _spotsFor(true);
    final expenseSpots = _spotsFor(false);
    final showIncome = _view != _TrendView.expense;
    final showExpense = _view != _TrendView.income;
    final visibleValues = <double>[
      if (showIncome) ...incomeSpots.map((spot) => spot.y),
      if (showExpense) ...expenseSpots.map((spot) => spot.y),
    ];
    final maxY = _niceMaxY(visibleValues);
    final maxX = math.max(1.0, (widget.days.length - 1).toDouble());
    final totalIncome = widget.days.fold<double>(
      0,
      (sum, day) => sum + (widget.daily[day]?.income ?? 0),
    );
    final totalExpense = widget.days.fold<double>(
      0,
      (sum, day) => sum + (widget.daily[day]?.expense ?? 0),
    );
    final net = totalIncome - totalExpense;
    final hasData = totalIncome != 0 || totalExpense != 0;
    final gridColor = scheme.outlineVariant.withOpacity(dark ? .16 : .42);
    final panelColor = dark
        ? scheme.surfaceContainerHigh.withOpacity(.46)
        : scheme.surface.withOpacity(.94);

    final bars = <LineChartBarData>[
      if (showIncome)
        LineChartBarData(
          spots: incomeSpots,
          isCurved: widget.days.length > 2,
          preventCurveOverShooting: true,
          barWidth: 3.2,
          isStrokeCapRound: true,
          color: kSleekIncome,
          dotData: FlDotData(show: false),
          belowBarData: BarAreaData(
            show: _view == _TrendView.income,
            color: kSleekIncome.withOpacity(dark ? .10 : .08),
          ),
        ),
      if (showExpense)
        LineChartBarData(
          spots: expenseSpots,
          isCurved: widget.days.length > 2,
          preventCurveOverShooting: true,
          barWidth: 3.2,
          isStrokeCapRound: true,
          color: kSleekExpense,
          dotData: FlDotData(show: false),
          belowBarData: BarAreaData(
            show: _view == _TrendView.expense,
            color: kSleekExpense.withOpacity(dark ? .10 : .08),
          ),
        ),
    ];

    return ExpressiveCard(
      surfaceTint: false,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Cash flow trend',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      widget.rangeLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ],
                ),
              ),
              Tooltip(
                message: 'Net cash flow',
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 116),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                  decoration: BoxDecoration(
                    color: (net >= 0 ? kSleekIncome : kSleekExpense).withOpacity(dark ? .10 : .08),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: (net >= 0 ? kSleekIncome : kSleekExpense).withOpacity(.22),
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        'Net',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                      Text(
                        state.format(net),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                              color: net >= 0 ? kSleekIncome : kSleekExpense,
                              fontWeight: FontWeight.w900,
                            ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                onPressed: () => showDateRangeSheet(context),
                tooltip: 'Change date range',
                icon: const Icon(Icons.date_range_rounded),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _TrendMetricPill(
                label: 'Income',
                value: state.format(totalIncome),
                icon: Icons.south_west_rounded,
                color: kSleekIncome,
              ),
              _TrendMetricPill(
                label: 'Expense',
                value: state.format(totalExpense),
                icon: Icons.north_east_rounded,
                color: kSleekExpense,
              ),
            ],
          ),
          const SizedBox(height: 14),
          SegmentedButton<_TrendView>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: _TrendView.both, label: Text('Both')),
              ButtonSegment(value: _TrendView.income, label: Text('Income')),
              ButtonSegment(value: _TrendView.expense, label: Text('Expense')),
            ],
            selected: {_view},
            onSelectionChanged: (selection) {
              if (selection.isNotEmpty) setState(() => _view = selection.first);
            },
          ),
          const SizedBox(height: 14),
          Container(
            height: 278,
            padding: const EdgeInsets.fromLTRB(6, 12, 10, 4),
            decoration: BoxDecoration(
              color: panelColor,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: scheme.outlineVariant.withOpacity(dark ? .14 : .48)),
            ),
            child: hasData
                ? RepaintBoundary(
                    child: LineChart(
                      LineChartData(
                        minX: 0,
                        maxX: maxX,
                        minY: 0,
                        maxY: maxY,
                        clipData: const FlClipData.all(),
                        borderData: FlBorderData(show: false),
                        gridData: FlGridData(
                          show: true,
                          drawVerticalLine: false,
                          horizontalInterval: maxY / 4,
                          getDrawingHorizontalLine: (_) => FlLine(color: gridColor, strokeWidth: 1),
                        ),
                        titlesData: FlTitlesData(
                          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                          leftTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 58,
                              interval: maxY / 4,
                              getTitlesWidget: (value, meta) => _leftTitle(context, value, meta, maxY),
                            ),
                          ),
                          bottomTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 36,
                              interval: 1,
                              getTitlesWidget: (value, meta) => _bottomTitle(context, value, meta),
                            ),
                          ),
                        ),
                        lineTouchData: LineTouchData(
                          handleBuiltInTouches: true,
                          touchTooltipData: LineTouchTooltipData(
                            tooltipRoundedRadius: 14,
                            tooltipPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                            tooltipMargin: 12,
                            getTooltipColor: (_) => dark ? const Color(0xFF142A22) : const Color(0xFF142A22),
                            getTooltipItems: (items) => items.map((item) {
                              final index = item.x.round().clamp(0, widget.days.length - 1).toInt();
                              final date = DateFormat('MMM d, yyyy').format(widget.days[index]);
                              final label = item.barIndex == 0 && showIncome ? 'Income' : 'Expense';
                              return LineTooltipItem(
                                '$date\n$label  ${_compactCurrency(state, item.y)}',
                                const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, height: 1.35),
                              );
                            }).toList(),
                          ),
                        ),
                        lineBarsData: bars,
                      ),
                    ),
                  )
                : Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.show_chart_rounded, size: 34, color: scheme.onSurfaceVariant.withOpacity(.65)),
                          const SizedBox(height: 10),
                          Text(
                            'No income or expense data in this range',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Add transactions or choose another date range to see a trend.',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                  ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              if (showIncome) const _TrendLegendDot(color: kSleekIncome, label: 'Income'),
              if (showIncome && showExpense) const SizedBox(width: 16),
              if (showExpense) const _TrendLegendDot(color: kSleekExpense, label: 'Expense'),
            ],
          ),
        ],
      ),
    );
  }
}

class _TrendMetricPill extends StatelessWidget {
  const _TrendMetricPill({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 112),
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
      decoration: BoxDecoration(
        color: color.withOpacity(Theme.of(context).brightness == Brightness.dark ? .10 : .08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 17, color: color),
          const SizedBox(width: 7),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w800,
                    ),
              ),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w900),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TrendLegendDot extends StatelessWidget {
  const _TrendLegendDot({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 7),
        Text(label, style: Theme.of(context).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w800)),
      ],
    );
  }
}

class CategoriesScreen extends StatefulWidget {
  const CategoriesScreen({super.key});

  @override
  State<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends State<CategoriesScreen> {
  CategoryType selected = CategoryType.expense;

  @override
  Widget build(BuildContext context) {
    return PageScaffold(
      title: 'Categories',
      subtitle: selected == CategoryType.expense ? 'Expense breakdown' : 'Income breakdown',
      actions: const [ProfileAvatarButton()],
      child: ResponsiveContent(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SleekCyclePillSelector<CategoryType>(
              options: const [
                SleekPillOption(value: CategoryType.expense, label: 'Expense', icon: Icons.north_east_rounded),
                SleekPillOption(value: CategoryType.income, label: 'Income', icon: Icons.south_west_rounded),
              ],
              selected: selected,
              onChanged: (v) => setState(() => selected = v),
            ),
            const SizedBox(height: 14),
            CategoryBreakdownCard(key: ValueKey(selected), type: selected, interactive: true),
            const SizedBox(height: 18),
            _ManageCategoriesButton(type: selected),
          ],
        ),
      ),
    );
  }
}

class _ManageCategoriesButton extends StatelessWidget {
  const _ManageCategoriesButton({required this.type});
  final CategoryType type;

  @override
  Widget build(BuildContext context) {
    final label = type == CategoryType.expense ? 'Expense categories' : 'Income categories';
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(.52),
      borderRadius: BorderRadius.circular(22),
      child: MotionInkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => ManageCategoriesScreen(type: type)),
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: Theme.of(context).colorScheme.outline.withOpacity(.28), width: .9),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: kSleekAccent.withOpacity(.16),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: kSleekAccent.withOpacity(.24)),
                ),
                child: const Icon(Icons.category_rounded, color: kSleekAccent),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Manage categories', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
                    const SizedBox(height: 3),
                    Text(
                      label,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: kSleekMuted, fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded),
            ],
          ),
        ),
      ),
    );
  }
}

class ManageCategoriesScreen extends StatelessWidget {
  const ManageCategoriesScreen({super.key, required this.type});
  final CategoryType type;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppController>();
    final cats = state.categories.where((c) => c.type == type).toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    final title = type == CategoryType.expense ? 'Expense categories' : 'Income categories';

    return PageScaffold(
      title: 'Manage categories',
      subtitle: title,
      actions: [IconButton(onPressed: () => showCategoryEditor(context, initialType: type), icon: const Icon(Icons.add_rounded))],
      child: ResponsiveListContent(
        itemCount: cats.length,
        empty: EmptyCard(
          icon: Icons.category_rounded,
          title: 'No ${enumName(type)} categories',
          body: 'Tap the + button to create a category.',
        ),
        itemBuilder: (context, index) {
          final category = cats[index];
          return CategoryTile(
            category: category,
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => showCategoryEditor(context, category: category),
          );
        },
      ),
    );
  }
}


class CategoryBreakdownCard extends StatelessWidget {
  const CategoryBreakdownCard({super.key, required this.type, this.interactive = false});
  final CategoryType type;
  final bool interactive;

  Color _fallbackColor(int index) {
    const palette = [
      Color(0xFF18D8CF),
      Color(0xFFA79BFF),
      Color(0xFF7EDBD3),
      Color(0xFF1EC7BD),
      Color(0xFFB9B1FF),
      Color(0xFF5BE6DB),
      Color(0xFFF7C66D),
      Color(0xFFF49DBE),
    ];
    return palette[index % palette.length];
  }

  List<_BreakdownSlice> _buildSlices(AppController state, List<MapEntry<String, double>> entries) {
    if (entries.length <= 8) {
      return entries.asMap().entries.map((indexed) {
        final index = indexed.key;
        final entry = indexed.value;
        final category = state.categoryOf(entry.key);
        final color = category == null ? _fallbackColor(index) : colorFromHex(category.iconColor, fallback: _fallbackColor(index));
        return _BreakdownSlice(categoryId: entry.key, category: category, value: entry.value, color: color);
      }).toList();
    }

    final visible = <_BreakdownSlice>[];
    for (var i = 0; i < 7; i++) {
      final entry = entries[i];
      final category = state.categoryOf(entry.key);
      final color = category == null ? _fallbackColor(i) : colorFromHex(category.iconColor, fallback: _fallbackColor(i));
      visible.add(_BreakdownSlice(categoryId: entry.key, category: category, value: entry.value, color: color));
    }
    final otherValue = entries.skip(7).fold<double>(0, (sum, entry) => sum + entry.value);
    visible.add(
      _BreakdownSlice(
        categoryId: '__other__',
        category: null,
        value: otherValue,
        color: _fallbackColor(7),
        labelOverride: 'Other',
        iconNameOverride: 'category',
      ),
    );
    return visible;
  }

  String _badgeTag(_BreakdownSlice slice) {
    if (slice.label.toLowerCase() == 'other') return 'OTHER';
    final words = slice.label
        .split(RegExp(r'\s+'))
        .where((w) => w.trim().isNotEmpty)
        .toList();
    if (words.isEmpty) return 'CAT';
    if (words.length >= 2) {
      return words.take(2).map((w) => w.substring(0, 1)).join().toUpperCase();
    }
    final word = words.first;
    if (word.length <= 4) return word.toUpperCase();
    return word.substring(0, 3).toUpperCase();
  }

  bool _useTextBadge(_BreakdownSlice slice) => slice.category == null;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppController>();
    final totals = state.categoryTotals(type);
    final entries = totals.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final total = entries.fold<double>(0, (sum, e) => sum + e.value);

    if (entries.isEmpty) {
      return ExpressiveCard(
        child: EmptyCard(
          icon: Icons.pie_chart_rounded,
          title: 'No ${enumName(type)} data',
          body: 'Transactions will appear here by category.',
        ),
      );
    }

    final slices = _buildSlices(state, entries);
    final chartTitle = type == CategoryType.expense ? 'Expense breakdown' : 'Income breakdown';
    final rangeLabel = state.activeRange().label;
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final chartSurfaceTop = isDark ? scheme.surfaceContainerHighest.withOpacity(.18) : const Color(0xFFF7FCFD);
    final chartSurfaceBottom = isDark ? scheme.surfaceContainerHigh.withOpacity(.06) : Colors.white;
    final chartBorderColor = isDark ? Colors.transparent : const Color(0xFFDCEBEE).withOpacity(.95);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ExpressiveCard(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                chartTitle,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: 334,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final canvasWidth = constraints.maxWidth;
                    const canvasHeight = 334.0;
                    final chartSize = math.min(math.max(180.0, canvasWidth - 98), math.min(268.0, canvasWidth - 8));
                    final centerSize = chartSize * .57;
                    final manyBadges = slices.length > 5;
                    final badgeWidth = manyBadges ? (canvasWidth < 360 ? 78.0 : 86.0) : (canvasWidth < 360 ? 84.0 : 94.0);
                    final badgeHeight = manyBadges ? 40.0 : 44.0;
                    final badgeOrbit = (chartSize / 2) + (manyBadges ? 32.0 : 24.0);

                    double startAngle = -90;
                    final badgeAngles = <double>[];
                    for (final slice in slices) {
                      final sweep = total == 0 ? 0 : (slice.value / total) * 360;
                      badgeAngles.add(startAngle + (sweep / 2));
                      startAngle += sweep;
                    }

                    final badgeNudges = List<double>.filled(slices.length, 0);
                    void spreadDenseSide(bool leftSide) {
                      final indexes = <int>[];
                      for (var i = 0; i < badgeAngles.length; i++) {
                        final radians = badgeAngles[i] * (math.pi / 180);
                        final isLeft = math.cos(radians) < -0.18;
                        if (isLeft == leftSide) indexes.add(i);
                      }
                      if (indexes.length <= 1) return;
                      indexes.sort((a, b) {
                        final ay = math.sin(badgeAngles[a] * (math.pi / 180));
                        final by = math.sin(badgeAngles[b] * (math.pi / 180));
                        return ay.compareTo(by);
                      });
                      final spacing = manyBadges ? 11.0 : 8.0;
                      for (var rank = 0; rank < indexes.length; rank++) {
                        badgeNudges[indexes[rank]] = (rank - ((indexes.length - 1) / 2)) * spacing;
                      }
                    }

                    spreadDenseSide(true);
                    spreadDenseSide(false);

                    int? selectedBadgeIndex;

                    return StatefulBuilder(
                      builder: (context, setBadgeState) {
                        return TweenAnimationBuilder<double>(
                      key: ValueKey('${type.name}-${slices.length}-${total.toStringAsFixed(2)}'),
                      tween: Tween<double>(begin: 0, end: 1),
                      duration: const Duration(milliseconds: 680),
                      curve: Curves.easeOutCubic,
                      builder: (context, progress, _) {
                        final badgeProgress = ((progress - .35) / .65).clamp(0.0, 1.0).toDouble();
                        final centerProgress = ((progress - .18) / .82).clamp(0.0, 1.0).toDouble();
                        final badgeOrder = List<int>.generate(slices.length, (index) => index);
                        if (selectedBadgeIndex != null && selectedBadgeIndex! >= 0 && selectedBadgeIndex! < slices.length) {
                          badgeOrder
                            ..remove(selectedBadgeIndex)
                            ..add(selectedBadgeIndex!);
                        }

                        return Stack(
                          alignment: Alignment.center,
                          clipBehavior: Clip.hardEdge,
                          children: [
                            Positioned.fill(
                              child: Container(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(34),
                                  gradient: LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [
                                      chartSurfaceTop,
                                      chartSurfaceBottom,
                                    ],
                                  ),
                                  border: Border.all(color: chartBorderColor, width: isDark ? 0.0 : 1.0),
                                  boxShadow: isDark
                                      ? null
                                      : [
                                          BoxShadow(
                                            color: Colors.black.withOpacity(.035),
                                            blurRadius: 18,
                                            offset: const Offset(0, 8),
                                          ),
                                        ],
                                ),
                              ),
                            ),
                            Center(
                              child: SizedBox(
                                width: chartSize,
                                height: chartSize,
                                child: RepaintBoundary(
                                  child: PieChart(
                                    PieChartData(
                                      startDegreeOffset: -90,
                                      sectionsSpace: 2.2,
                                      centerSpaceRadius: chartSize * .285,
                                      sections: slices.asMap().entries.map((entry) {
                                        final selected = selectedBadgeIndex == entry.key;
                                        return PieChartSectionData(
                                          value: entry.value.value,
                                          color: entry.value.color,
                                          radius: (chartSize * (selected ? .135 : .118)) * progress,
                                          showTitle: false,
                                        );
                                      }).toList(),
                                    ),
                                    swapAnimationDuration: const Duration(milliseconds: 260),
                                    swapAnimationCurve: Curves.easeOutCubic,
                                  ),
                                ),
                              ),
                            ),
                            for (final i in badgeOrder)
                              _DonutBadgePositioned(
                                angleDegrees: badgeAngles[i],
                                orbit: badgeOrbit,
                                canvasWidth: canvasWidth,
                                canvasHeight: canvasHeight,
                                badgeWidth: selectedBadgeIndex == i ? badgeWidth + 12 : badgeWidth,
                                badgeHeight: selectedBadgeIndex == i ? badgeHeight + 4 : badgeHeight,
                                verticalNudge: badgeNudges[i],
                                child: GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTap: () {
                                    setBadgeState(() {
                                      selectedBadgeIndex = selectedBadgeIndex == i ? null : i;
                                    });
                                  },
                                  child: Opacity(
                                    opacity: badgeProgress,
                                    child: Transform.scale(
                                      scale: (.86 + (.14 * badgeProgress)) * (selectedBadgeIndex == i ? 1.08 : 1.0),
                                      child: _DonutPercentBadge(
                                        color: slices[i].color,
                                        iconName: slices[i].iconName,
                                        label: total <= 0 ? '0%' : '${((slices[i].value / total) * 100).round()}%',
                                        leadingText: _badgeTag(slices[i]),
                                        useTextBadge: _useTextBadge(slices[i]),
                                        selected: selectedBadgeIndex == i,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            Center(
                              child: Opacity(
                                opacity: centerProgress,
                                child: Transform.scale(
                                  scale: .92 + (.08 * centerProgress),
                                  child: Container(
                                    width: centerSize,
                                    height: centerSize,
                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                    decoration: BoxDecoration(
                                      color: isDark ? const Color(0xFF101A15).withOpacity(.97) : Colors.white.withOpacity(.98),
                                      shape: BoxShape.circle,
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withOpacity(isDark ? .22 : .08),
                                          blurRadius: isDark ? 22.0 : 18.0,
                                          offset: const Offset(0, 10),
                                        ),
                                      ],
                                      border: Border.all(
                                        color: isDark ? scheme.outline.withOpacity(.10) : const Color(0xFFD7E6E9),
                                      ),
                                    ),
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Flexible(
                                          flex: 3,
                                          child: FittedBox(
                                            fit: BoxFit.scaleDown,
                                            child: Text(
                                              state.format(total),
                                              maxLines: 1,
                                              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                                                    fontWeight: FontWeight.w900,
                                                    letterSpacing: -.8,
                                                    color: isDark ? Colors.white : scheme.onSurface,
                                                  ),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(height: 5),
                                        Flexible(
                                          flex: 2,
                                          child: FittedBox(
                                            fit: BoxFit.scaleDown,
                                            child: Text(
                                              type == CategoryType.expense ? 'Total expense' : 'Total income',
                                              maxLines: 1,
                                              textAlign: TextAlign.center,
                                              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                                    color: kSleekAccent,
                                                    fontWeight: FontWeight.w900,
                                                  ),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(height: 3),
                                        Flexible(
                                          flex: 2,
                                          child: FittedBox(
                                            fit: BoxFit.scaleDown,
                                            child: Text(
                                              rangeLabel,
                                              maxLines: 1,
                                              textAlign: TextAlign.center,
                                              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                                    color: isDark ? Colors.white.withOpacity(.82) : scheme.onSurfaceVariant.withOpacity(.88),
                                                    fontWeight: FontWeight.w800,
                                                  ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        ...slices.asMap().entries.map((indexed) {
          final slice = indexed.value;
          final color = slice.color;
          final percentage = total <= 0 ? 0.0 : (slice.value / total) * 100;

          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: ExpressiveCard(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Material(
                color: Colors.transparent,
                child: MotionInkWell(
                  borderRadius: BorderRadius.circular(18),
                  onTap: interactive && slice.category != null
                      ? () => Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => CategoryTransactionScreen(category: slice.category!)),
                          )
                      : null,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
                    child: Row(
                      children: [
                        iconBubble(context, slice.iconName, colorToHex(color), size: 50),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                slice.label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${percentage.toStringAsFixed(1)}%',
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: kSleekMuted, fontWeight: FontWeight.w800),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          state.format(slice.value),
                          style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900),
                        ),
                        if (interactive && slice.category != null) ...[
                          const SizedBox(width: 8),
                          Icon(Icons.chevron_right_rounded, color: Theme.of(context).colorScheme.onSurfaceVariant),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        }),
      ],
    );
  }
}

class _BreakdownSlice {
  const _BreakdownSlice({
    required this.categoryId,
    required this.category,
    required this.value,
    required this.color,
    this.labelOverride,
    this.iconNameOverride,
  });

  final String categoryId;
  final Category? category;
  final double value;
  final Color color;
  final String? labelOverride;
  final String? iconNameOverride;

  String get label => labelOverride ?? category?.name ?? 'Unknown';
  String get iconName => iconNameOverride ?? category?.iconName ?? 'category';
}

class _DonutBadgePositioned extends StatelessWidget {
  const _DonutBadgePositioned({
    required this.angleDegrees,
    required this.orbit,
    required this.canvasWidth,
    required this.canvasHeight,
    required this.badgeWidth,
    required this.badgeHeight,
    this.verticalNudge = 0,
    required this.child,
  });

  final double angleDegrees;
  final double orbit;
  final double canvasWidth;
  final double canvasHeight;
  final double badgeWidth;
  final double badgeHeight;
  final double verticalNudge;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final radians = angleDegrees * (math.pi / 180);
    final center = Offset(canvasWidth / 2, canvasHeight / 2);
    final rawLeft = center.dx + math.cos(radians) * orbit - (badgeWidth / 2);
    final rawTop = center.dy + math.sin(radians) * orbit - (badgeHeight / 2) + verticalNudge;
    final left = rawLeft.clamp(0.0, math.max(0.0, canvasWidth - badgeWidth)).toDouble();
    final top = rawTop.clamp(0.0, math.max(0.0, canvasHeight - badgeHeight)).toDouble();

    return Positioned(
      left: left,
      top: top,
      width: badgeWidth,
      height: badgeHeight,
      child: child,
    );
  }
}

class _DonutPercentBadge extends StatelessWidget {
  const _DonutPercentBadge({
    required this.color,
    required this.iconName,
    required this.label,
    required this.leadingText,
    required this.useTextBadge,
    this.selected = false,
  });

  final Color color;
  final String iconName;
  final String label;
  final String leadingText;
  final bool useTextBadge;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final badgeBackground = selected
        ? (isDark ? color.withOpacity(.28) : color.withOpacity(.20))
        : (isDark ? const Color(0xFF151E19).withOpacity(.96) : Colors.white.withOpacity(.96));
    final badgeBorder = selected ? color.withOpacity(isDark ? .88 : .72) : (isDark ? Colors.white.withOpacity(.05) : kSleekLightOutlineVariant);
    final textColor = isDark ? Colors.white.withOpacity(.96) : scheme.onSurface;
    final iconBackground = useTextBadge
        ? (isDark ? Colors.black : kSleekLightSurfaceContainer)
        : color.withOpacity(isDark ? .18 : .16);
    final iconBorder = useTextBadge
        ? (isDark ? Colors.white.withOpacity(.06) : kSleekLightOutlineVariant)
        : color.withOpacity(isDark ? .28 : .30);
    final iconColor = isDark ? Colors.white : color;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 6),
      decoration: BoxDecoration(
        color: badgeBackground,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: badgeBorder, width: selected ? 2.0 : 1.0),
        boxShadow: [
          BoxShadow(
            color: selected ? color.withOpacity(isDark ? .34 : .22) : Colors.black.withOpacity(isDark ? .26 : .10),
            blurRadius: selected ? 22.0 : (isDark ? 18.0 : 14.0),
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: iconBackground,
              shape: BoxShape.circle,
              border: Border.all(color: iconBorder),
            ),
            child: Center(
              child: useTextBadge
                  ? FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 5),
                        child: Text(
                          leadingText,
                          maxLines: 1,
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                color: textColor,
                                fontWeight: FontWeight.w900,
                                letterSpacing: .4,
                              ),
                        ),
                      ),
                    )
                  : iconGlyph(context, iconName, color: iconColor, size: 15, imageBackground: Colors.white.withOpacity(.90)),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                label,
                maxLines: 1,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                      letterSpacing: -.2,
                      color: textColor,
                    ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class CategoryTransactionScreen extends StatelessWidget {
  const CategoryTransactionScreen({super.key, required this.category});
  final Category category;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppController>();
    final txs = state.filteredTransactions(categoryId: category.id, ignoreDate: true);
    return PageScaffold(
      title: category.name,
      subtitle: '${txs.length} transactions',
      actions: [IconButton(onPressed: () => showTransactionEditor(context, lockedCategory: category), icon: const Icon(Icons.add_rounded))],
      child: ResponsiveListContent(
        itemCount: txs.length,
        empty: const EmptyCard(icon: Icons.receipt_long_rounded, title: 'No transactions', body: 'Transactions for this category will appear here.'),
        itemBuilder: (context, index) => TransactionTile(tx: txs[index]),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Budgets
// -----------------------------------------------------------------------------

class BudgetListScreen extends StatelessWidget {
  const BudgetListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppController>();
    final progress = state.budgetProgress();
    return PageScaffold(
      title: 'Budgets',
      actions: [IconButton(onPressed: () => showBudgetEditor(context), icon: const Icon(Icons.add_rounded))],
      child: ResponsiveContent(
        child: progress.isEmpty
            ? EmptyCard(icon: Icons.savings_rounded, title: 'No budgets', body: 'Create a monthly budget for all accounts/categories or selected scopes.', action: () => showBudgetEditor(context), actionLabel: 'Create budget', animated: true)
            : Column(
                children: progress
                    .map(
                      (p) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: BudgetProgressTile(
                          progress: p,
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => BudgetDetailScreen(progress: p),
                            ),
                          ),
                        ),
                      ),
                    )
                    .toList(),
              ),
      ),
    );
  }
}

class BudgetProgressTile extends StatelessWidget {
  const BudgetProgressTile({super.key, required this.progress, this.onTap});
  final BudgetProgress progress;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppController>();
    final ratio = progress.ratio;
    final color = ratio >= 1 ? Colors.red : ratio >= .8 ? Colors.deepOrange : ratio >= .5 ? Colors.orange : Colors.green;
    return ExpressiveCard(
      child: MotionInkWell(
        borderRadius: BorderRadius.circular(28),
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              iconBubble(context, 'wallet', colorToHex(color)),
              const SizedBox(width: 12),
              Expanded(child: Text(DateFormat('MMMM yyyy').format(progress.budget.selectedMonth), style: const TextStyle(fontWeight: FontWeight.w900))),
              Text('${(ratio * 100).clamp(0, 999).toStringAsFixed(0)}%', style: const TextStyle(fontWeight: FontWeight.w900)),
            ]),
            const SizedBox(height: 12),
            ClipRRect(borderRadius: BorderRadius.circular(99), child: LinearProgressIndicator(value: ratio.clamp(0, 1).toDouble(), minHeight: 12, color: color)),
            const SizedBox(height: 8),
            Text('${state.format(progress.spent)} spent of ${state.format(progress.budget.amount)}'),
          ],
        ),
      ),
    );
  }
}

class BudgetDetailScreen extends StatelessWidget {
  const BudgetDetailScreen({super.key, required this.progress});
  final BudgetProgress progress;

  @override
  Widget build(BuildContext context) {
    return PageScaffold(
      title: 'Budget detail',
      subtitle: DateFormat('MMMM yyyy').format(progress.budget.selectedMonth),
      actions: [IconButton(onPressed: () => showBudgetEditor(context, budget: progress.budget), icon: const Icon(Icons.edit_rounded)), IconButton(onPressed: () => showTransactionEditor(context), icon: const Icon(Icons.add_rounded))],
      child: ResponsiveContent(
        child: Column(
          children: [
            BudgetProgressTile(progress: progress),
            const SectionHeader('Transactions under this budget'),
            if (progress.transactions.isEmpty) const EmptyCard(icon: Icons.receipt_long_rounded, title: 'No spending', body: 'Spending matching this budget scope will appear here.') else ...progress.transactions.map((tx) => Padding(padding: const EdgeInsets.only(bottom: 10), child: TransactionTile(tx: tx))),
          ],
        ),
      ),
    );
  }
}

Future<void> showBudgetEditor(BuildContext context, {Budget? budget}) async {
  await showKoinlyPopup<void>(
    context,
    maxWidth: 560,
    maxHeight: 700,
    child: BudgetEditor(budget: budget),
  );
}

class BudgetEditor extends StatefulWidget {
  const BudgetEditor({super.key, this.budget});
  final Budget? budget;

  @override
  State<BudgetEditor> createState() => _BudgetEditorState();
}

class _BudgetEditorState extends State<BudgetEditor> {
  final amount = TextEditingController();
  DateTime month = DateTime(DateTime.now().year, DateTime.now().month);
  bool allAccounts = true;
  bool allCategories = true;
  List<String> accountIds = [];
  List<String> categoryIds = [];

  @override
  void initState() {
    super.initState();
    final b = widget.budget;
    if (b != null) {
      amount.text = b.amount.toStringAsFixed(2);
      month = b.selectedMonth;
      allAccounts = b.allAccountsSelected;
      allCategories = b.allCategoriesSelected;
      accountIds = List.of(b.accountIds);
      categoryIds = List.of(b.categoryIds);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppController>();
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 18, 14, 14),
      child: KoinlyPopupContent(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.budget == null ? 'Create budget' : 'Edit budget', textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900)),
            const SizedBox(height: 16),
            TextField(
              onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
              controller: amount, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Budget amount')),
            const SizedBox(height: 12),
            OutlinedButton.icon(onPressed: () async { final d = await pickDate(context, month); if (d != null) setState(() => month = DateTime(d.year, d.month)); }, icon: const Icon(Icons.calendar_month_rounded), label: Text(DateFormat('MMMM yyyy').format(month))),
            SwitchListTile(value: allAccounts, onChanged: (v) => setState(() => allAccounts = v), title: const Text('Apply to all accounts')),
            if (!allAccounts) Wrap(spacing: 8, runSpacing: 8, children: state.accounts.map((a) => FilterChip(label: Text(a.name), selected: accountIds.contains(a.id), onSelected: (v) => setState(() => v ? accountIds.add(a.id) : accountIds.remove(a.id)))).toList()),
            SwitchListTile(value: allCategories, onChanged: (v) => setState(() => allCategories = v), title: const Text('Apply to all categories')),
            if (!allCategories) Wrap(spacing: 8, runSpacing: 8, children: state.categories.where((c) => c.type == CategoryType.expense).map((c) => FilterChip(label: Text(c.name), selected: categoryIds.contains(c.id), onSelected: (v) => setState(() => v ? categoryIds.add(c.id) : categoryIds.remove(c.id)))).toList()),
            const SizedBox(height: 18),
            Row(children: [
              if (widget.budget != null) Expanded(child: OutlinedButton(onPressed: () async { await state.deleteBudget(widget.budget!.id); if (context.mounted) Navigator.pop(context); }, child: const Text('Delete'))),
              if (widget.budget != null) const SizedBox(width: 12),
              Expanded(flex: 2, child: FilledButton(onPressed: () async {
                final value = double.tryParse(amount.text) ?? 0;
                if (value <= 0) return;
                final now = DateTime.now();
                final budget = Budget(id: widget.budget?.id ?? _uuid.v4(), selectedMonth: month, amount: value, allAccountsSelected: allAccounts, allCategoriesSelected: allCategories, accountIds: allAccounts ? [] : accountIds, categoryIds: allCategories ? [] : categoryIds, createdOn: widget.budget?.createdOn ?? now, updatedOn: now);
                await state.saveBudget(budget);
                if (context.mounted) Navigator.pop(context);
              }, child: const Text('Save'))),
            ]),
          ],
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Settings, backup, about
// -----------------------------------------------------------------------------

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppController>();
    return PageScaffold(
      title: 'Settings',
      child: ResponsiveContent(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        child: Column(
          children: [
            SettingsTile(icon: Icons.palette_rounded, title: 'Theme', subtitle: _themeLabel(state.themePreference), color: '#A6E3A1', onTap: () => showThemeDialog(context)),
            SettingsTile(icon: Icons.payments_rounded, title: 'Currency customization', subtitle: '${state.currencyCode} • ${state.currencyPosition == CurrencyPosition.prefix ? 'Prefix' : 'Suffix'}', color: kSleekAccentHex, onTap: () => showCurrencySheet(context)),
            SettingsTile(icon: Icons.notifications_active_rounded, title: 'Reminder notification', subtitle: state.reminderEnabled ? 'Daily at ${state.reminderTime.format(context)}' : 'Disabled', color: '#FBC879', onTap: () => showReminderSheet(context)),
            SettingsTile(icon: Icons.cloud_sync_rounded, title: 'Account & sync', subtitle: state.cloudSyncEnabled ? '${state.syncStatus} • ${state.syncAccountUsername}' : 'Sign in for multi-device sync', color: kSleekAccentHex, onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MultiDeviceSyncScreen()))),
            SettingsTile(icon: Icons.system_update_alt_rounded, title: 'Updates', subtitle: state.updateStatusMessage, color: kSleekAccentHex, onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const UpdatesScreen()))),
            SettingsTile(icon: Icons.filter_alt_rounded, title: 'Default date filter', subtitle: _dateRangeLabel(state.dateRangeType), color: '#B4A5FF', onTap: () => showDateRangeSheet(context)),
            SettingsTile(icon: Icons.tune_rounded, title: 'Advanced settings', subtitle: 'Defaults, backup, data health', color: '#9AD0F5', onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AdvancedSettingsScreen()))),
            SettingsTile(icon: Icons.info_rounded, title: 'About app', subtitle: 'Version, credits, licenses, and links', color: '#86E3CE', onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AboutScreen()))),
          ],
        ),
      ),
    );
  }
}


class SettingsTile extends StatelessWidget {
  const SettingsTile({super.key, required this.icon, required this.title, this.subtitle, required this.color, this.onTap});
  final IconData icon;
  final String title;
  final String? subtitle;
  final String color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = colorFromHex(color);
    final hasSubtitle = subtitle != null && subtitle!.trim().isNotEmpty;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: MotionTouchFeedback(
        enabled: onTap != null,
        scale: .987,
        child: ExpressiveCard(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: hasSubtitle ? 12 : 14),
          child: ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: c.withOpacity(.16),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: c.withOpacity(.20)),
            ),
            child: Icon(icon, color: c),
          ),
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
          subtitle: hasSubtitle
              ? Text(
                  subtitle!,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: kSleekMuted, fontWeight: FontWeight.w700),
                )
              : null,
          trailing: Icon(Icons.chevron_right_rounded, color: Theme.of(context).colorScheme.onSurfaceVariant),
            onTap: onTap,
          ),
        ),
      ),
    );
  }
}

class UpdatesScreen extends StatelessWidget {
  const UpdatesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppController>();
    final release = state.latestGithubRelease;
    final releaseDate = release?.publishedAt == null ? 'Not available' : DateFormat('MMM d, yyyy • h:mm a').format(release!.publishedAt!.toLocal());
    return PageScaffold(
      title: 'Updates',
      subtitle: updateRepositorySlug,
      child: ResponsiveContent(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ExpressiveCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      iconBubble(context, 'download', kSleekAccentHex, size: 54),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Koinly updates', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
                            const SizedBox(height: 4),
                            Text(state.updateStatusMessage, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: kSleekMuted, fontWeight: FontWeight.w700)),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  MiniMetric('Installed version', appVersion, Icons.phone_android_rounded),
                  const SizedBox(height: 10),
                  MiniMetric('Latest version', release?.displayVersion ?? 'Not checked', Icons.new_releases_rounded),
                  const SizedBox(height: 10),
                  MiniMetric('Release date', releaseDate, Icons.event_rounded),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: state.updateCheckBusy
                        ? null
                        : () async {
                            final result = await context.read<AppController>().checkForUpdates(manual: true);
                            if (context.mounted && result.hasUpdate) {
                              await showUpdateBottomSheet(context);
                            }
                          },
                    icon: state.updateCheckBusy
                        ? const KoinlyInlineLoader(size: 18)
                        : const Icon(Icons.refresh_rounded),
                    label: Text(state.updateCheckBusy ? 'Checking...' : 'Check for updates'),
                  ),
                  if (state.hasAvailableUpdate) ...[
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: () => showUpdateBottomSheet(context),
                      icon: const Icon(Icons.system_update_alt_rounded),
                      label: const Text('Show update details'),
                    ),
                  ],
                  const SizedBox(height: 12),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    value: state.automaticUpdatePopupEnabled,
                    onChanged: (value) => context.read<AppController>().setAutomaticUpdatePopupEnabled(value),
                    title: const Text('Automatic update pop-ups', style: TextStyle(fontWeight: FontWeight.w900)),
                    subtitle: Text(
                      'Show update details automatically and send a notification when a newer Koinly release is found. Manual update checks still work when this is off.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: kSleekMuted, fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ),
            if (release != null) ...[
              const SectionHeader('Latest release changelog'),
              ExpressiveCard(child: ReleaseChangelogView(markdown: release.body)),
            ],
          ],
        ),
      ),
    );
  }
}

Future<void> showUpdateBottomSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (sheetContext) {
      return DraggableScrollableSheet(
        expand: false,
        initialChildSize: .84,
        minChildSize: .48,
        maxChildSize: .96,
        builder: (context, scrollController) {
          return Consumer<AppController>(
            builder: (context, state, _) {
              final release = state.latestGithubRelease;
              if (release == null) {
                return ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(18, 10, 18, 24),
                  children: const [EmptyCard(icon: Icons.system_update_alt_rounded, title: 'No update details', body: 'Check for updates first.')],
                );
              }
              final releaseDate = release.publishedAt == null ? 'Release date unavailable' : DateFormat('MMM d, yyyy').format(release.publishedAt!.toLocal());
              return ListView(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(18, 10, 18, 24),
                children: [
                  Row(
                    children: [
                      iconBubble(context, 'download', kSleekAccentHex, size: 54),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Update ${release.displayVersion}', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900)),
                            const SizedBox(height: 3),
                            Text(releaseDate, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: kSleekMuted, fontWeight: FontWeight.w800)),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  ExpressiveCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text("What's New", style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
                        const SizedBox(height: 10),
                        ReleaseChangelogView(markdown: release.body),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  const UpdateActionPanel(),
                  const SizedBox(height: 10),
                  TextButton(onPressed: () => Navigator.pop(sheetContext), child: const Text('Later')),
                ],
              );
            },
          );
        },
      );
    },
  );
}

class UpdateActionPanel extends StatelessWidget {
  const UpdateActionPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppController>();
    if (Platform.isAndroid) return _AndroidUpdateActionPanel(state: state);
    if (Platform.isWindows) return _WindowsUpdateActionPanel(state: state);
    return ExpressiveCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Download update', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          Text('Open the GitHub release page for this platform.', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: kSleekMuted, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: () {
              final url = state.latestGithubRelease?.htmlUrl;
              if (url != null && url.isNotEmpty) launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
            },
            icon: const Icon(Icons.open_in_new_rounded),
            label: const Text('Open release page'),
          ),
        ],
      ),
    );
  }
}

class _AndroidUpdateActionPanel extends StatelessWidget {
  const _AndroidUpdateActionPanel({required this.state});

  final AppController state;

  @override
  Widget build(BuildContext context) {
    final assets = state.availableAndroidUpdateAssets;
    if (assets.isEmpty) {
      return const EmptyCard(icon: Icons.android_rounded, title: 'No Android APK found', body: 'This GitHub release does not include ARM64, ARM32, x86_64, or Universal APK assets.');
    }
    if (state.updateDownloadBusy && state.updateDownloadProgress != null) {
      return DownloadProgressCard(
        architecture: state.selectedAndroidUpdateKind.label,
        progress: state.updateDownloadProgress!,
        onCancel: () => unawaited(state.cancelUpdateDownload()),
      );
    }

    final pendingKind = state.pendingAndroidUpdateKind;
    final pendingVersion = state.pendingAndroidUpdateVersion;
    return ExpressiveCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Android architecture', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: assets.entries.map((entry) {
              final selected = state.selectedAndroidUpdateKind == entry.key;
              final sizeText = entry.value.sizeBytes > 0 ? ' • ${formatBytes(entry.value.sizeBytes)}' : '';
              return ChoiceChip(
                selected: selected,
                label: Text('${entry.key.label}$sizeText'),
                onSelected: (_) => context.read<AppController>().selectAndroidUpdateKind(entry.key),
              );
            }).toList(),
          ),
          if (pendingKind != null && pendingVersion == state.latestGithubRelease?.displayVersion) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => unawaited(state.installPendingAndroidUpdate()),
              icon: const Icon(Icons.install_mobile_rounded),
              label: Text('Install ${pendingKind.label} update'),
            ),
          ],
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: state.selectedAndroidUpdateAsset == null ? null : () => unawaited(state.downloadSelectedAndroidUpdate()),
            icon: const Icon(Icons.download_rounded),
            label: const Text('Download update'),
          ),
        ],
      ),
    );
  }
}

class _WindowsUpdateActionPanel extends StatelessWidget {
  const _WindowsUpdateActionPanel({required this.state});

  final AppController state;

  @override
  Widget build(BuildContext context) {
    final asset = state.windowsUpdateInstallerAsset;
    if (state.updateDownloadBusy && state.updateDownloadProgress != null) {
      return DownloadProgressCard(
        architecture: 'Windows installer',
        progress: state.updateDownloadProgress!,
        onCancel: () => unawaited(state.cancelUpdateDownload()),
      );
    }
    if (asset == null) {
      return ExpressiveCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Windows installer', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
            Text(
              'This release does not include a Windows installer asset.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: kSleekMuted, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () {
                final url = state.latestGithubRelease?.htmlUrl;
                if (url != null && url.isNotEmpty) {
                  launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
                }
              },
              icon: const Icon(Icons.open_in_new_rounded),
              label: const Text('Open release page'),
            ),
          ],
        ),
      );
    }

    final pendingForThisRelease = state.hasPendingWindowsUpdate &&
        state.pendingWindowsUpdateVersion == state.latestGithubRelease?.displayVersion;
    return ExpressiveCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Windows installer', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          Text(
            '${asset.name}${asset.sizeBytes > 0 ? ' • ${formatBytes(asset.sizeBytes)}' : ''}',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: kSleekMuted, fontWeight: FontWeight.w700),
          ),
          if (pendingForThisRelease) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => unawaited(state.installPendingWindowsUpdate()),
              icon: const Icon(Icons.install_desktop_rounded),
              label: const Text('Install downloaded update'),
            ),
          ],
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: () => unawaited(state.downloadWindowsUpdate(force: pendingForThisRelease)),
            icon: const Icon(Icons.download_rounded),
            label: Text(pendingForThisRelease ? 'Re-download installer' : 'Download update'),
          ),
        ],
      ),
    );
  }
}

class DownloadProgressCard extends StatelessWidget {
  const DownloadProgressCard({super.key, required this.architecture, required this.progress, required this.onCancel});

  final String architecture;
  final DownloadProgressSnapshot progress;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return ExpressiveCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text('Downloading $architecture', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900))),
              Text('${progress.percent}%', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900, color: kSleekAccent)),
            ],
          ),
          const SizedBox(height: 12),
          WaveProgressIndicator(progress: progress.fraction),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: Text('${progress.downloadedText} / ${progress.totalText}', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: kSleekMuted, fontWeight: FontWeight.w800))),
              Text(progress.speedText, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: kSleekMuted, fontWeight: FontWeight.w800)),
            ],
          ),
          const SizedBox(height: 6),
          Text(progress.status, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: progress.percent >= 100 ? kSleekIncome : kSleekAccent, fontWeight: FontWeight.w900)),
          const SizedBox(height: 10),
          OutlinedButton.icon(onPressed: onCancel, icon: const Icon(Icons.close_rounded), label: const Text('Cancel download')),
        ],
      ),
    );
  }
}

class WaveProgressIndicator extends StatefulWidget {
  const WaveProgressIndicator({super.key, required this.progress});

  final double progress;

  @override
  State<WaveProgressIndicator> createState() => _WaveProgressIndicatorState();
}

class _WaveProgressIndicatorState extends State<WaveProgressIndicator> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1050),
    );
    _syncControllerState();
  }

  @override
  void didUpdateWidget(covariant WaveProgressIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncControllerState();
  }

  void _syncControllerState() {
    if (widget.progress >= 1) {
      if (_controller.isAnimating) _controller.stop();
      return;
    }
    if (!_controller.isAnimating) _controller.repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 92,
      child: RepaintBoundary(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) => CustomPaint(
            painter: _WaveProgressPainter(
              progress: widget.progress,
              phase: _controller.value,
              color: kSleekAccent,
            ),
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );
  }
}

class _WaveProgressPainter extends CustomPainter {
  const _WaveProgressPainter({required this.progress, required this.phase, required this.color});

  final double progress;
  final double phase;
  final Color color;

  Path _wavePath(Size size, double fillTop, double phaseOffset, double amplitude) {
    final path = Path()
      ..moveTo(0, size.height)
      ..lineTo(0, fillTop);
    for (double x = 0; x <= size.width + 4; x += 4) {
      final normalizedX = x / math.max(1, size.width);
      final angle = (normalizedX * math.pi * 2) + ((phase + phaseOffset) * math.pi * 2);
      path.lineTo(x, fillTop + math.sin(angle) * amplitude);
    }
    return path
      ..lineTo(size.width, size.height)
      ..close();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final radius = BorderRadius.circular(24);
    final rect = Offset.zero & size;
    final rrect = radius.toRRect(rect);
    final clampedProgress = progress.clamp(0.0, 1.0).toDouble();

    canvas.drawRRect(rrect, Paint()..color = kSleekSurfaceHigher.withValues(alpha: .72));
    canvas.save();
    canvas.clipRRect(rrect);

    final fillTop = size.height * (1 - clampedProgress);
    final backWave = _wavePath(size, fillTop + 3, .42, 5.5);
    final frontWave = _wavePath(size, fillTop, 0, 7.5);

    final backPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [color.withValues(alpha: .38), color.withValues(alpha: .18)],
      ).createShader(rect);
    canvas.drawPath(backWave, backPaint);

    final frontPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [color.withValues(alpha: .96), color.withValues(alpha: .48)],
      ).createShader(rect);
    canvas.drawPath(frontWave, frontPaint);

    final highlightY = (fillTop + math.sin(phase * math.pi * 2) * 2.5).clamp(0.0, size.height).toDouble();
    canvas.drawLine(
      Offset(0, highlightY),
      Offset(size.width, highlightY),
      Paint()
        ..color = Colors.white.withValues(alpha: .16)
        ..strokeWidth = 1,
    );

    canvas.restore();
    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = color.withValues(alpha: .34),
    );
  }

  @override
  bool shouldRepaint(covariant _WaveProgressPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.phase != phase || oldDelegate.color != color;
}

class ReleaseChangelogView extends StatelessWidget {
  const ReleaseChangelogView({super.key, required this.markdown});

  final String markdown;

  @override
  Widget build(BuildContext context) {
    final blocks = ChangelogParser.parse(markdown);
    if (blocks.isEmpty) {
      return Text('No changelog was provided for this release.', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: kSleekMuted, fontWeight: FontWeight.w700));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: blocks.map((block) => _ChangelogBlockView(block: block)).toList(),
    );
  }
}

class _ChangelogBlockView extends StatelessWidget {
  const _ChangelogBlockView({required this.block});

  final ChangelogBlock block;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    switch (block.type) {
      case ChangelogBlockType.heading:
        return Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 6),
          child: Text(block.plainText, style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
        );
      case ChangelogBlockType.bullet:
        return _ChangelogLine(prefix: '•', block: block);
      case ChangelogBlockType.numbered:
        return _ChangelogLine(prefix: '${block.number ?? 1}.', block: block);
      case ChangelogBlockType.paragraph:
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: _LinkedSegmentsText(segments: block.segments),
        );
    }
  }
}

class _ChangelogLine extends StatelessWidget {
  const _ChangelogLine({required this.prefix, required this.block});

  final String prefix;
  final ChangelogBlock block;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 24, child: Text(prefix, style: const TextStyle(fontWeight: FontWeight.w900, color: kSleekAccent))),
          Expanded(child: _LinkedSegmentsText(segments: block.segments)),
        ],
      ),
    );
  }
}

class _LinkedSegmentsText extends StatelessWidget {
  const _LinkedSegmentsText({required this.segments});

  final List<MarkdownTextSegment> segments;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.35, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: .92), fontWeight: FontWeight.w700);
    return Wrap(
      children: segments.map((segment) {
        final segmentStyle = segment.bold ? style?.copyWith(fontWeight: FontWeight.w900) : style;
        if (segment.url == null) return Text(segment.text, style: segmentStyle);
        return MotionInkWell(
          onTap: () => launchUrl(Uri.parse(segment.url!), mode: LaunchMode.externalApplication),
          child: Text(segment.text, style: segmentStyle?.copyWith(color: kSleekAccent, decoration: TextDecoration.underline, fontWeight: FontWeight.w900)),
        );
      }).toList(),
    );
  }
}

class MultiDeviceSyncScreen extends StatefulWidget {
  const MultiDeviceSyncScreen({
    super.key,
    this.completeOnAuth = false,
    this.returnOnAuth = false,
    this.initialRegisterMode = false,
    this.preferCloudDataOnAuth = true,
  });

  final bool completeOnAuth;
  final bool returnOnAuth;
  final bool initialRegisterMode;
  final bool preferCloudDataOnAuth;

  @override
  State<MultiDeviceSyncScreen> createState() => _MultiDeviceSyncScreenState();
}

class _MultiDeviceSyncScreenState extends State<MultiDeviceSyncScreen> {
  late final TextEditingController _usernameController;
  late final TextEditingController _passwordController;
  late final TextEditingController _workerUrlController;
  bool _obscurePassword = true;
  bool _endpointBusy = false;
  late bool _registerMode;

  @override
  void initState() {
    super.initState();
    final state = context.read<AppController>();
    _usernameController = TextEditingController(text: state.syncAccountUsername);
    _passwordController = TextEditingController();
    _workerUrlController = TextEditingController(text: state.selfHostedSyncApiBaseUrl);
    _registerMode = widget.initialRegisterMode;
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _workerUrlController.dispose();
    super.dispose();
  }

  Future<void> _saveSyncEndpoint() async {
    final state = context.read<AppController>();
    final wasSignedIn = state.cloudSyncEnabled;
    setState(() => _endpointBusy = true);
    try {
      await state.configureSelfHostedSyncEndpoint(_workerUrlController.text);
      if (!mounted) return;
      _workerUrlController.text = state.selfHostedSyncApiBaseUrl;
      showSnack(
        context,
        wasSignedIn && !state.cloudSyncEnabled
            ? 'Self-hosted Worker changed. Sign in to this Worker.'
            : 'Self-hosted Worker validated and enabled.',
      );
    } catch (error) {
      if (mounted) {
        showSnack(context, redactSyncSecrets(error.toString().replaceFirst('Bad state: ', '').replaceFirst('Exception: ', '')));
      }
    } finally {
      if (mounted) setState(() => _endpointBusy = false);
    }
  }

  Future<void> _login({required bool register}) async {
    final state = context.read<AppController>();
    final onboardingAuthFlow = widget.completeOnAuth || widget.returnOnAuth;
    if (!_isWorkerActive(state)) {
      showSnack(context, 'Validate and use the self-hosted Worker first.');
      return;
    }
    if (_usernameController.text.trim().isEmpty || _passwordController.text.isEmpty) {
      showSnack(context, 'Enter username and password.');
      return;
    }
    final usernameError = _syncUsernameValidationError(_usernameController.text);
    if (usernameError != null) {
      showSnack(context, usernameError);
      return;
    }
    final normalizedUsername = _usernameController.text.trim().toLowerCase();
    _usernameController.value = _usernameController.value.copyWith(
      text: normalizedUsername,
      selection: TextSelection.collapsed(offset: normalizedUsername.length),
      composing: TextRange.empty,
    );
    String? recoveryKey;
    if (register) {
      recoveryKey = await state.registerSyncAccount(
        username: normalizedUsername,
        password: _passwordController.text,
        deferInitialDataSync: onboardingAuthFlow,
      );
    } else {
      await state.loginSyncAccount(
        username: normalizedUsername,
        password: _passwordController.text,
        preferCloudData: onboardingAuthFlow ? true : widget.preferCloudDataOnAuth,
      );
    }
    if (mounted && state.cloudSyncError == null) {
      _passwordController.clear();
      if (register && recoveryKey != null && recoveryKey.isNotEmpty) {
        await _showRecoveryKey(recoveryKey);
        if (!mounted) return;
      }
      showSnack(
        context,
        register
            ? onboardingAuthFlow
                ? 'Account created. Choose Restore backup or Start new.'
                : 'Account created. Sync started.'
            : 'Signed in. Cloud data loaded.',
      );
      if (register && onboardingAuthFlow) {
        if (mounted) Navigator.pop(context, true);
      } else if (!register && onboardingAuthFlow) {
        await state.completeOnboarding();
        if (mounted) Navigator.pop(context, false);
      } else if (widget.returnOnAuth) {
        if (mounted) Navigator.pop(context, false);
      }
    }
  }

  Future<void> _showRecoveryKey(String recoveryKey) async {
    await showKoinlyPopup<void>(
      context,
      maxWidth: 520,
      maxHeight: 430,
      barrierDismissible: false,
      child: _RecoveryKeyPopup(recoveryKey: recoveryKey),
    );
  }

  Future<void> _showForgotPassword() async {
    final state = context.read<AppController>();
    if (!_isWorkerActive(state)) {
      showSnack(context, 'Validate and use the self-hosted Worker first.');
      return;
    }
    final recovered = await showKoinlyPopup<bool>(
      context,
      maxWidth: 540,
      maxHeight: 620,
      barrierDismissible: false,
      child: _AccountRecoveryPopup(
        initialUsername: _usernameController.text.trim(),
        preferCloudData: widget.completeOnAuth || widget.returnOnAuth ? true : widget.preferCloudDataOnAuth,
      ),
    );
    if (!mounted || recovered != true) return;
    _usernameController.text = state.syncAccountUsername;
    _passwordController.clear();
    showSnack(context, 'Password changed and account recovered.');
    final onboardingAuthFlow = widget.completeOnAuth || widget.returnOnAuth;
    if (onboardingAuthFlow) {
      await state.completeOnboarding();
      if (mounted) Navigator.pop(context, false);
    }
  }

  Future<void> _rotateRecoveryKey() async {
    final state = context.read<AppController>();
    final recoveryKey = await state.rotateSyncRecoveryKey();
    if (!mounted) return;
    if (recoveryKey == null || recoveryKey.isEmpty) {
      showSnack(context, state.cloudSyncError ?? 'Could not create a recovery key.');
      return;
    }
    await _showRecoveryKey(recoveryKey);
  }

  Future<void> _restoreCloudCopy() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Merge cloud copy?'),
        content: const Text('This downloads the cloud data for this account and merges it with this device. Local-only data is kept, matching entity IDs are reconciled, and duplicate categories such as Food are combined instead of copied twice.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Merge cloud')),
        ],
      ),
    );
    if (confirmed != true) return;
    final state = context.read<AppController>();
    await state.syncFromCloud();
    if (!mounted) return;
    showSnack(context, state.cloudSyncError == null ? 'Cloud data merged with this device.' : state.cloudSyncError!);
  }

  Future<void> _uploadPendingChanges() async {
    final state = context.read<AppController>();
    if (state.cloudSyncOperationBusy) {
      showSnack(context, 'Sync is already running. Please wait a moment.');
      return;
    }
    await state.syncToCloud(force: true);
    if (!mounted) return;
    const successMessage = 'Local and cloud changes merged successfully.';
    showSnack(context, state.cloudSyncError == null ? successMessage : state.cloudSyncError!);
  }

  bool _isWorkerActive(AppController state) {
    final activeUrl = CloudSyncService.normalizeApiBaseUrl(state.cloudSyncApiBaseUrl);
    final selectedUrl = CloudSyncService.normalizeApiBaseUrl(_workerUrlController.text);
    return selectedUrl.isNotEmpty && selectedUrl == activeUrl;
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppController>();
    final signedIn = state.cloudSyncEnabled && state.syncAccountUsername.isNotEmpty;
    final busy = state.cloudSyncOperationBusy || _endpointBusy;
    const uploadButtonLabel = 'Upload local changes';
    final backendConfigured = _isWorkerActive(state);
    return PageScaffold(
      title: 'Account & sync',
      subtitle: signedIn ? state.syncAccountUsername : 'Self-hosted multi-device sync',
      actions: [
        IconButton.filledTonal(
          tooltip: 'Telegram backup',
          onPressed: busy
              ? null
              : () {
                  if (!backendConfigured) {
                    showSnack(context, 'Validate and use the self-hosted Worker first.');
                    return;
                  }
                  if (!signedIn) {
                    showSnack(context, 'Sign in to the self-hosted Worker before configuring Telegram backups.');
                    return;
                  }
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const SelfHostedTelegramBackupScreen()));
                },
          icon: const Icon(Icons.smart_toy_rounded),
        ),
      ],
      child: ResponsiveContent(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ExpressiveCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Self-hosted Sync Worker', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
                  const SizedBox(height: 6),
                  Text(
                    'Enter the HTTPS URL from your own Cloudflare Worker deployment.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: kSleekMuted, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
                    controller: _workerUrlController,
                    enabled: !busy,
                    keyboardType: TextInputType.url,
                    autocorrect: false,
                    enableSuggestions: false,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      labelText: 'Cloudflare Worker URL',
                      hintText: 'https://my-sync.example.workers.dev',
                      prefixIcon: Icon(Icons.link_rounded),
                    ),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: busy ? null : _saveSyncEndpoint,
                    icon: _endpointBusy
                        ? const KoinlyInlineLoader(size: 18)
                        : const Icon(Icons.verified_rounded),
                    label: const Text('Validate and use Worker'),
                  ),
                  if (signedIn) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Changing the Worker signs out this device because each self-hosted deployment has separate accounts and tokens.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: kSleekMuted, fontWeight: FontWeight.w700),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),
            ExpressiveCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          color: kSleekAccent.withOpacity(.15),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: kSleekAccent.withOpacity(.24)),
                        ),
                        child: Icon(signedIn ? Icons.cloud_done_rounded : Icons.cloud_off_rounded, color: kSleekAccent),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(state.syncStatus, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
                            const SizedBox(height: 4),
                            Text(
                              state.cloudSyncLastAt == null ? 'Not synced yet' : 'Last synced ${DateFormat('MMM d, yyyy HH:mm').format(state.cloudSyncLastAt!.toLocal())}',
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: kSleekMuted, fontWeight: FontWeight.w700),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (state.cloudSyncError != null && state.cloudSyncError!.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(state.cloudSyncError!, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: kSleekExpense, fontWeight: FontWeight.w800)),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
              controller: _usernameController,
              enabled: !busy && !signedIn,
              keyboardType: TextInputType.text,
              autocorrect: false,
              enableSuggestions: false,
              textCapitalization: TextCapitalization.none,
              decoration: const InputDecoration(labelText: 'Username', prefixIcon: Icon(Icons.person_rounded)),
            ),
            const SizedBox(height: 12),
            if (!signedIn)
              TextField(
                onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
                controller: _passwordController,
                enabled: !busy,
                obscureText: _obscurePassword,
                decoration: InputDecoration(
                  labelText: 'Password',
                  prefixIcon: const Icon(Icons.lock_rounded),
                  suffixIcon: IconButton(
                    onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                    icon: Icon(_obscurePassword ? Icons.visibility_rounded : Icons.visibility_off_rounded),
                  ),
                ),
              ),
            const SizedBox(height: 16),
            if (!signedIn) ...[
              Text(
                _registerMode ? 'Create your Koinly sync account' : 'Login to your Koinly sync account',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
              ),
              if (_registerMode) ...[
                const SizedBox(height: 8),
                Text(
                  'Only the first account can be created on a new self-hosted Worker. After that, sign in with that account on your other devices.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: kSleekMuted, fontWeight: FontWeight.w800),
                ),
              ] else ...[
                const SizedBox(height: 8),
                Text(
                  'Login merges your cloud copy with finance data already on this device. Local-only records are preserved.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: kSleekMuted, fontWeight: FontWeight.w800),
                ),
              ],
              const SizedBox(height: 10),
            ],
            if (signedIn)
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: busy ? null : _restoreCloudCopy,
                          icon: busy
                              ? const KoinlyInlineLoader(size: 18)
                              : const Icon(Icons.cloud_download_rounded),
                          label: const Text('Restore cloud copy'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: busy ? null : _uploadPendingChanges,
                          icon: const Icon(Icons.cloud_upload_rounded),
                          label: Text(uploadButtonLabel),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: busy ? null : _rotateRecoveryKey,
                          icon: const Icon(Icons.key_rounded),
                          label: const Text('Recovery key'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: busy ? null : () => state.logoutSyncAccount(),
                          icon: const Icon(Icons.logout_rounded),
                          label: const Text('Sign out'),
                        ),
                      ),
                    ],
                  ),
                ],
              )
            else
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  FilledButton.icon(
                    onPressed: busy || !backendConfigured ? null : () => _login(register: _registerMode),
                    icon: busy
                        ? const KoinlyInlineLoader(size: 18)
                        : Icon(_registerMode ? Icons.person_add_alt_rounded : Icons.login_rounded),
                    label: Text(_registerMode ? 'Create account' : 'Login'),
                  ),
                  OutlinedButton.icon(
                    onPressed: busy ? null : () => setState(() => _registerMode = !_registerMode),
                    icon: Icon(_registerMode ? Icons.login_rounded : Icons.person_add_alt_rounded),
                    label: Text(_registerMode ? 'Use login instead' : 'Create account instead'),
                  ),
                  if (!_registerMode)
                    TextButton.icon(
                      onPressed: busy || !backendConfigured ? null : _showForgotPassword,
                      icon: const Icon(Icons.lock_reset_rounded),
                      label: const Text('Forgot password?'),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _RecoveryKeyPopup extends StatelessWidget {
  const _RecoveryKeyPopup({required this.recoveryKey});

  final String recoveryKey;

  @override
  Widget build(BuildContext context) {
    return KoinlyPopupContent(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(Icons.key_rounded, size: 42, color: kSleekAccent),
          const SizedBox(height: 12),
          Text('Save your recovery key', textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          Text(
            'This key is the only in-app way to reset a forgotten password. Store it somewhere safe. Creating a new recovery key invalidates the previous one.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: kSleekMuted, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(.45),
              borderRadius: BorderRadius.circular(18),
            ),
            child: SelectableText(recoveryKey, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w900, letterSpacing: .8)),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: recoveryKey));
                    if (context.mounted) showSnack(context, 'Recovery key copied.');
                  },
                  icon: const Icon(Icons.copy_rounded),
                  label: const Text('Copy'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.check_rounded),
                  label: const Text('I saved it'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AccountRecoveryPopup extends StatefulWidget {
  const _AccountRecoveryPopup({required this.initialUsername, required this.preferCloudData});

  final String initialUsername;
  final bool preferCloudData;

  @override
  State<_AccountRecoveryPopup> createState() => _AccountRecoveryPopupState();
}

class _AccountRecoveryPopupState extends State<_AccountRecoveryPopup> {
  late final TextEditingController username;
  final recoveryKey = TextEditingController();
  final password = TextEditingController();
  final confirmPassword = TextEditingController();
  bool obscurePassword = true;
  bool busy = false;

  @override
  void initState() {
    super.initState();
    username = TextEditingController(text: widget.initialUsername);
  }

  @override
  void dispose() {
    username.dispose();
    recoveryKey.dispose();
    password.dispose();
    confirmPassword.dispose();
    super.dispose();
  }

  Future<void> _recover() async {
    if (busy) return;
    final usernameValue = username.text.trim().toLowerCase();
    final recoveryValue = recoveryKey.text.trim();
    if (usernameValue.isEmpty || recoveryValue.isEmpty || password.text.isEmpty || confirmPassword.text.isEmpty) {
      showSnack(context, 'Complete all recovery fields.');
      return;
    }
    final usernameError = _syncUsernameValidationError(usernameValue);
    if (usernameError != null) {
      showSnack(context, usernameError);
      return;
    }
    if (password.text != confirmPassword.text) {
      showSnack(context, 'Passwords do not match.');
      return;
    }
    if (password.text.length < 8) {
      showSnack(context, 'Password must be at least 8 characters.');
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => busy = true);
    final state = context.read<AppController>();
    await state.recoverSyncAccount(
      username: usernameValue,
      recoveryKey: recoveryValue,
      newPassword: password.text,
      preferCloudData: widget.preferCloudData,
    );
    if (!mounted) return;
    if (state.cloudSyncError != null) {
      setState(() => busy = false);
      showSnack(context, state.cloudSyncError!);
      return;
    }
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return KoinlyPopupContent(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text('Recover account', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900))),
              IconButton(onPressed: busy ? null : () => Navigator.pop(context, false), icon: const Icon(Icons.close_rounded)),
            ],
          ),
          const SizedBox(height: 6),
          Text('Enter your username, saved recovery key, and a new password.', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: kSleekMuted, fontWeight: FontWeight.w700)),
          const SizedBox(height: 14),
          TextField(
            onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
            controller: username,
            enabled: !busy,
            autocorrect: false,
            enableSuggestions: false,
            textCapitalization: TextCapitalization.none,
            decoration: const InputDecoration(labelText: 'Username', prefixIcon: Icon(Icons.person_rounded)),
          ),
          const SizedBox(height: 10),
          TextField(
            onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
            controller: recoveryKey,
            enabled: !busy,
            autocorrect: false,
            enableSuggestions: false,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(labelText: 'Recovery key', prefixIcon: Icon(Icons.key_rounded)),
          ),
          const SizedBox(height: 10),
          TextField(
            onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
            controller: password,
            enabled: !busy,
            obscureText: obscurePassword,
            decoration: InputDecoration(
              labelText: 'New password',
              prefixIcon: const Icon(Icons.lock_rounded),
              suffixIcon: IconButton(
                onPressed: busy ? null : () => setState(() => obscurePassword = !obscurePassword),
                icon: Icon(obscurePassword ? Icons.visibility_rounded : Icons.visibility_off_rounded),
              ),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
            controller: confirmPassword,
            enabled: !busy,
            obscureText: obscurePassword,
            onSubmitted: (_) => _recover(),
            decoration: const InputDecoration(labelText: 'Confirm new password', prefixIcon: Icon(Icons.lock_outline_rounded)),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: busy ? null : _recover,
            icon: busy ? const KoinlyInlineLoader(size: 18) : const Icon(Icons.lock_reset_rounded),
            label: Text(busy ? 'Recovering...' : 'Reset password'),
          ),
        ],
      ),
    );
  }
}

class SelfHostedTelegramBackupScreen extends StatefulWidget {
  const SelfHostedTelegramBackupScreen({super.key});

  @override
  State<SelfHostedTelegramBackupScreen> createState() => _SelfHostedTelegramBackupScreenState();
}

class _SelfHostedTelegramBackupScreenState extends State<SelfHostedTelegramBackupScreen> {
  final _botTokenController = TextEditingController();
  final _chatIdController = TextEditingController();
  TelegramBackupSettings _settings = const TelegramBackupSettings.defaults();
  bool _loading = true;
  bool _busy = false;
  bool _obscureToken = true;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _botTokenController.dispose();
    _chatIdController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final settings = await context.read<AppController>().loadSelfHostedTelegramBackupSettings();
      if (!mounted) return;
      setState(() {
        _settings = settings;
        _chatIdController.text = settings.chatId;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _loading = false);
      final message = error.toString().replaceFirst('Bad state: ', '').replaceFirst('Exception: ', '');
      final normalized = message.toLowerCase();
      showSnack(
        context,
        normalized.contains('not found') || normalized.contains('404')
            ? 'This self-hosted Worker is older than the Telegram-backup feature. Redeploy it from the latest Koinly workflow, then try again.'
            : message,
      );
    }
  }

  Future<void> _save() async {
    final chatId = _chatIdController.text.trim();
    if (_settings.enabled && chatId.isEmpty) {
      showSnack(context, 'Enter the Telegram group or channel Chat ID.');
      return;
    }
    if (_settings.enabled && !_settings.tokenConfigured && _botTokenController.text.trim().isEmpty) {
      showSnack(context, 'Enter a Telegram bot token before enabling backups.');
      return;
    }
    setState(() => _busy = true);
    try {
      final state = context.read<AppController>();
      if (_settings.enabled) {
        await state.syncToCloud(force: true, silent: false);
        if (state.cloudSyncError != null) {
          throw StateError('Could not sync local data before enabling Telegram backups: ${state.cloudSyncError}');
        }
      }
      final settings = await state.saveSelfHostedTelegramBackupSettings(
            enabled: _settings.enabled,
            botToken: _botTokenController.text,
            chatId: chatId,
            frequency: _settings.frequency,
            hour: _settings.hour,
            minute: _settings.minute,
            weekday: _settings.weekday,
            monthDay: _settings.monthDay,
          );
      if (!mounted) return;
      _botTokenController.clear();
      setState(() {
        _settings = settings;
        _chatIdController.text = settings.chatId;
      });
      showSnack(context, settings.enabled ? 'Telegram backup schedule saved.' : 'Telegram automatic backups are off.');
    } catch (error) {
      if (mounted) showSnack(context, error.toString().replaceFirst('Bad state: ', '').replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _test() async {
    final chatId = _chatIdController.text.trim();
    if (chatId.isEmpty && _settings.chatId.isEmpty) {
      showSnack(context, 'Enter the Telegram group or channel Chat ID first.');
      return;
    }
    if (!_settings.tokenConfigured && _botTokenController.text.trim().isEmpty) {
      showSnack(context, 'Enter the Telegram bot token first.');
      return;
    }
    setState(() => _busy = true);
    try {
      await context.read<AppController>().testSelfHostedTelegramBackup(
            botToken: _botTokenController.text,
            chatId: chatId,
          );
      if (mounted) showSnack(context, 'Telegram bot connected successfully. Check the target chat.');
    } catch (error) {
      if (mounted) showSnack(context, error.toString().replaceFirst('Bad state: ', '').replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sendNow() async {
    if (!_settings.tokenConfigured || _settings.chatId.trim().isEmpty) {
      showSnack(context, 'Save the Telegram bot and destination first.');
      return;
    }
    setState(() => _busy = true);
    try {
      await context.read<AppController>().sendSelfHostedTelegramBackupNow();
      if (!mounted) return;
      showSnack(context, 'Cloud backup uploaded to Telegram.');
      await _load();
    } catch (error) {
      if (mounted) showSnack(context, error.toString().replaceFirst('Bad state: ', '').replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: _settings.hour, minute: _settings.minute),
    );
    if (picked == null || !mounted) return;
    setState(() => _settings = TelegramBackupSettings(
          enabled: _settings.enabled,
          tokenConfigured: _settings.tokenConfigured,
          chatId: _settings.chatId,
          frequency: _settings.frequency,
          hour: picked.hour,
          minute: picked.minute,
          weekday: _settings.weekday,
          monthDay: _settings.monthDay,
          timezoneOffsetMinutes: DateTime.now().timeZoneOffset.inMinutes,
          nextDueAt: _settings.nextDueAt,
          lastSentAt: _settings.lastSentAt,
          lastError: _settings.lastError,
        ));
  }

  TelegramBackupSettings _copySettings({
    bool? enabled,
    TelegramBackupFrequency? frequency,
    int? weekday,
    int? monthDay,
  }) {
    return TelegramBackupSettings(
      enabled: enabled ?? _settings.enabled,
      tokenConfigured: _settings.tokenConfigured,
      chatId: _settings.chatId,
      frequency: frequency ?? _settings.frequency,
      hour: _settings.hour,
      minute: _settings.minute,
      weekday: weekday ?? _settings.weekday,
      monthDay: monthDay ?? _settings.monthDay,
      timezoneOffsetMinutes: DateTime.now().timeZoneOffset.inMinutes,
      nextDueAt: _settings.nextDueAt,
      lastSentAt: _settings.lastSentAt,
      lastError: _settings.lastError,
    );
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

  String _offsetLabel() {
    final offset = DateTime.now().timeZoneOffset;
    final totalMinutes = offset.inMinutes;
    final sign = totalMinutes >= 0 ? '+' : '-';
    final absolute = totalMinutes.abs();
    final hours = absolute ~/ 60;
    final minutes = absolute % 60;
    return 'UTC$sign${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}';
  }

  String _formatServerTime(DateTime? value) {
    if (value == null) return 'Not yet';
    return DateFormat('MMM d, yyyy • h:mm a').format(value.toLocal());
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const PageScaffold(
        title: 'Telegram backup',
        subtitle: 'Self-hosted Sync Worker',
        child: const KoinlyPageLoader(),
      );
    }

    final time = TimeOfDay(hour: _settings.hour, minute: _settings.minute).format(context);
    return PageScaffold(
      title: 'Telegram backup',
      subtitle: 'Self-hosted Sync Worker only',
      child: ResponsiveContent(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 36),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ExpressiveCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    value: _settings.enabled,
                    onChanged: _busy ? null : (value) => setState(() => _settings = _copySettings(enabled: value)),
                    title: const Text('Automatic Telegram backup', style: TextStyle(fontWeight: FontWeight.w900)),
                    subtitle: const Text('The self-hosted Worker creates a .koinlybackup from the cloud copy and uploads it to your Telegram group or channel.'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            ExpressiveCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Telegram bot', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
                  const SizedBox(height: 12),
                  TextField(
                    onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
                    controller: _botTokenController,
                    enabled: !_busy,
                    obscureText: _obscureToken,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: InputDecoration(
                      labelText: _settings.tokenConfigured ? 'Bot token (saved)' : 'Bot token',
                      hintText: _settings.tokenConfigured ? 'Leave blank to keep the current token' : '123456789:AA...',
                      prefixIcon: const Icon(Icons.smart_toy_rounded),
                      suffixIcon: IconButton(
                        onPressed: () => setState(() => _obscureToken = !_obscureToken),
                        icon: Icon(_obscureToken ? Icons.visibility_rounded : Icons.visibility_off_rounded),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
                    controller: _chatIdController,
                    enabled: !_busy,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: const InputDecoration(
                      labelText: 'Group or channel Chat ID',
                      hintText: '-1001234567890 or @channelname',
                      prefixIcon: Icon(Icons.forum_rounded),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Add the bot to the target group/channel. For a channel, make the bot an administrator with permission to post messages. The bot token is encrypted by your Worker before it is stored in Turso.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: kSleekMuted, fontWeight: FontWeight.w700, height: 1.35),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _test,
                    icon: const Icon(Icons.verified_rounded),
                    label: const Text('Test bot and destination'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            ExpressiveCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('When to upload', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
                  const SizedBox(height: 12),
                  SegmentedButton<TelegramBackupFrequency>(
                    segments: const [
                      ButtonSegment(value: TelegramBackupFrequency.daily, label: Text('Daily')),
                      ButtonSegment(value: TelegramBackupFrequency.weekly, label: Text('Weekly')),
                      ButtonSegment(value: TelegramBackupFrequency.monthly, label: Text('Monthly')),
                    ],
                    selected: {_settings.frequency},
                    onSelectionChanged: _busy ? null : (value) => setState(() => _settings = _copySettings(frequency: value.first)),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _pickTime,
                    icon: const Icon(Icons.schedule_rounded),
                    label: Text('Time · $time'),
                  ),
                  if (_settings.frequency == TelegramBackupFrequency.weekly) ...[
                    const SizedBox(height: 12),
                    DropdownButtonFormField<int>(
                      value: _settings.weekday,
                      decoration: const InputDecoration(labelText: 'Day of week', prefixIcon: Icon(Icons.calendar_view_week_rounded)),
                      items: List.generate(7, (index) {
                        final weekday = index + 1;
                        return DropdownMenuItem(value: weekday, child: Text(_weekdayLabel(weekday)));
                      }),
                      onChanged: _busy
                          ? null
                          : (value) {
                              if (value == null) return;
                              setState(() => _settings = _copySettings(weekday: value));
                            },
                    ),
                  ],
                  if (_settings.frequency == TelegramBackupFrequency.monthly) ...[
                    const SizedBox(height: 12),
                    DropdownButtonFormField<int>(
                      value: _settings.monthDay,
                      decoration: const InputDecoration(labelText: 'Day of month', prefixIcon: Icon(Icons.calendar_month_rounded)),
                      items: List.generate(31, (index) => DropdownMenuItem(value: index + 1, child: Text('Day ${index + 1}'))),
                      onChanged: _busy
                          ? null
                          : (value) {
                              if (value == null) return;
                              setState(() => _settings = _copySettings(monthDay: value));
                            },
                    ),
                  ],
                  const SizedBox(height: 10),
                  Text(
                    'Schedule uses this device timezone (${_offsetLabel()}). The Worker checks due schedules every 5 minutes, so delivery can occur a few minutes after the selected time.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: kSleekMuted, fontWeight: FontWeight.w700, height: 1.35),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            ExpressiveCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Status', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
                  const SizedBox(height: 8),
                  Text('Last uploaded: ${_formatServerTime(_settings.lastSentAt)}', style: const TextStyle(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  Text('Next scheduled: ${_settings.enabled ? _formatServerTime(_settings.nextDueAt) : 'Automatic upload is off'}', style: const TextStyle(fontWeight: FontWeight.w800)),
                  if ((_settings.lastError ?? '').trim().isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(_settings.lastError!, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: kSleekExpense, fontWeight: FontWeight.w800)),
                  ],
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _busy || !_settings.tokenConfigured || _settings.chatId.trim().isEmpty ? null : _sendNow,
                    icon: const Icon(Icons.send_rounded),
                    label: const Text('Upload backup now'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: _busy ? null : _save,
              icon: _busy
                  ? const KoinlyInlineLoader(size: 18)
                  : const Icon(Icons.save_rounded),
              label: const Text('Save Telegram backup settings'),
            ),
          ],
        ),
      ),
    );
  }
}

class CloudSyncScreen extends StatefulWidget {
  const CloudSyncScreen({super.key});

  @override
  State<CloudSyncScreen> createState() => _CloudSyncScreenState();
}

class _CloudSyncScreenState extends State<CloudSyncScreen> {
  late final TextEditingController _syncIdController;
  late final TextEditingController _pinController;
  bool _obscurePin = true;

  @override
  void initState() {
    super.initState();
    final state = context.read<AppController>();
    _syncIdController = TextEditingController(text: state.cloudSyncId);
    _pinController = TextEditingController(text: state.cloudSyncPin);
  }

  @override
  void dispose() {
    _syncIdController.dispose();
    _pinController.dispose();
    super.dispose();
  }

  Future<void> _saveSettings({bool showStatus = true}) async {
    final state = context.read<AppController>();
    await state.configureCloudSync(
      enabled: true,
      apiBaseUrl: state.cloudSyncApiBaseUrl,
      syncId: _syncIdController.text,
      pin: _pinController.text,
    );
    if (!mounted || !showStatus) return;
    showSnack(context, 'Online sync settings saved.');
  }

  Future<void> _syncNow() async {
    // Sync merges the latest database/cloud data into this device.
    await _downloadNow();
  }

  Future<void> _uploadNow() async {
    await _saveSettings(showStatus: false);
    final state = context.read<AppController>();
    await state.syncMainOnlineToCloud(force: true);
    if (!mounted) return;
    _syncIdController.text = state.cloudSyncId;
    _pinController.text = state.cloudSyncPin;
    await _showSyncResult('Local and cloud data merged, then uploaded.');
  }

  Future<void> _downloadNow() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Merge from Database?'),
        content: const Text('This downloads the latest database data and merges it with this device. Local-only records stay, matching IDs are reconciled, and duplicate categories are combined.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Merge')),
        ],
      ),
    );
    if (confirmed != true) return;
    await _saveSettings(showStatus: false);
    final state = context.read<AppController>();
    await state.syncMainOnlineFromCloud();
    if (!mounted) return;
    await _showSyncResult('Database data merged with this device.');
  }

  Future<void> _showSyncResult(String successMessage) async {
    final state = context.read<AppController>();
    if (state.cloudSyncApprovalRequired) {
      await _showActivationDialog();
      return;
    }
    showSnack(context, state.cloudSyncError == null ? successMessage : state.cloudSyncError!);
  }

  Future<void> _showActivationDialog() async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Message admin to activate your online sync.'),
        content: const Text('Your Sync ID is waiting for admin approval. After the admin approves it, press Sync again.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
          FilledButton.icon(
            onPressed: () async {
              await launchUrl(Uri.parse(kSyncAdminTelegramUrl), mode: LaunchMode.externalApplication);
            },
            icon: const Icon(Icons.send_rounded),
            label: const Text('Telegram'),
          ),
        ],
      ),
    );
  }

  Future<void> _openAdvancedSettings() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const SyncDatabaseMethodsScreen()),
    );
    if (!mounted) return;
    final state = context.read<AppController>();
    setState(() {
      _syncIdController.text = state.cloudSyncId;
      _pinController.text = state.cloudSyncPin;
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppController>();
    return PageScaffold(
      title: 'Online data sync',
      actions: [
        Material(
          color: Colors.transparent,
          child: MotionInkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: _openAdvancedSettings,
            child: Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(.55),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Theme.of(context).colorScheme.outline.withOpacity(.14)),
              ),
              child: const Icon(Icons.more_vert_rounded, size: 30),
            ),
          ),
        ),
      ],
      child: ResponsiveContent(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
              controller: _syncIdController,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Sync ID',
                hintText: 'Example: siam-main-wallet',
                prefixIcon: Icon(Icons.badge_rounded),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
              controller: _pinController,
              obscureText: _obscurePin,
              decoration: InputDecoration(
                labelText: 'Sync PIN',
                hintText: 'Minimum 4 characters',
                prefixIcon: const Icon(Icons.password_rounded),
                suffixIcon: IconButton(
                  onPressed: () => setState(() => _obscurePin = !_obscurePin),
                  icon: Icon(_obscurePin ? Icons.visibility_rounded : Icons.visibility_off_rounded),
                ),
              ),
            ),
            if (state.cloudSyncError != null && state.cloudSyncError!.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(state.cloudSyncError!, style: TextStyle(color: Theme.of(context).colorScheme.error, fontWeight: FontWeight.w800)),
            ],
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: state.cloudSyncBusy || state.syncDatabaseProvider == SyncDatabaseProvider.local ? null : _syncNow,
              icon: state.cloudSyncBusy
                  ? const KoinlyInlineLoader(size: 18)
                  : const Icon(Icons.cloud_sync_rounded),
              label: const Text('Sync'),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: state.cloudSyncBusy || state.syncDatabaseProvider == SyncDatabaseProvider.local ? null : _uploadNow,
              icon: const Icon(Icons.cloud_upload_rounded),
              label: const Text('Upload Data'),
            ),
            const SizedBox(height: 14),
            Text(
              'Important: Sync downloads/restores the latest database data to this device. Upload Data uploads this device’s local data to the configured database. Automatic sync still runs after local changes once a database method is configured. Conflict handling is last-upload-wins.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: kSleekMuted, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
}

class SyncDatabaseMethodsScreen extends StatelessWidget {
  const SyncDatabaseMethodsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return PageScaffold(
      title: 'Hidden Settings',
      child: ResponsiveContent(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ExpressiveCard(
              padding: const EdgeInsets.all(18),
              child: MotionInkWell(
                borderRadius: BorderRadius.circular(22),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SyncDatabaseMethodListScreen()),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: kSleekAccent.withOpacity(.15),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Icon(Icons.cloud_sync_rounded, color: kSleekAccent),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        'Select database method',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
                      ),
                    ),
                    Icon(Icons.chevron_right_rounded, color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class SyncDatabaseMethodListScreen extends StatelessWidget {
  const SyncDatabaseMethodListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppController>();
    return PageScaffold(
      title: 'Select database method',
      child: ResponsiveContent(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ...userSyncDatabaseProviders.map(
              (provider) => _ProviderChoiceCard(
                provider: provider,
                selected: state.syncDatabaseProvider == provider,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => SyncDatabaseProviderConfigScreen(provider: provider)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class SyncDatabaseProviderConfigScreen extends StatefulWidget {
  const SyncDatabaseProviderConfigScreen({super.key, required this.provider});

  final SyncDatabaseProvider provider;

  @override
  State<SyncDatabaseProviderConfigScreen> createState() => _SyncDatabaseProviderConfigScreenState();
}

class _SyncDatabaseProviderConfigScreenState extends State<SyncDatabaseProviderConfigScreen> {
  late final TextEditingController _apiBaseUrlController;
  late final TextEditingController _mongoUrlController;
  late final TextEditingController _mongoDatabaseController;
  late final TextEditingController _mongoCollectionController;
  late final TextEditingController _mongoSyncIdController;
  late final TextEditingController _mongoSyncPinController;
  late final TextEditingController _tursoDatabaseUrlController;
  late final TextEditingController _tursoAuthTokenController;
  bool _obscureMongoUrl = true;
  bool _testing = false;
  String? _status;

  SyncDatabaseProvider get _provider => widget.provider;

  @override
  void initState() {
    super.initState();
    final state = context.read<AppController>();
    _apiBaseUrlController = TextEditingController(text: state.cloudSyncApiBaseUrl);
    _mongoUrlController = TextEditingController(text: state.syncMongoDbUrl);
    _mongoDatabaseController = TextEditingController(text: state.syncMongoDatabaseName);
    _mongoCollectionController = TextEditingController(text: state.syncMongoCollectionName);
    _mongoSyncIdController = TextEditingController(text: state.syncMongoSyncId);
    _mongoSyncPinController = TextEditingController(text: state.syncMongoSyncPin);
    _tursoDatabaseUrlController = TextEditingController(text: state.syncTursoDatabaseUrl);
    _tursoAuthTokenController = TextEditingController(text: state.syncTursoAuthToken);
  }

  @override
  void dispose() {
    _apiBaseUrlController.dispose();
    _mongoUrlController.dispose();
    _mongoDatabaseController.dispose();
    _mongoCollectionController.dispose();
    _mongoSyncIdController.dispose();
    _mongoSyncPinController.dispose();
    _tursoDatabaseUrlController.dispose();
    _tursoAuthTokenController.dispose();
    super.dispose();
  }

  Future<void> _testConnection() async {
    final state = context.read<AppController>();
    setState(() {
      _testing = true;
      _status = null;
    });
    try {
      await state.testSyncDatabaseConnection(
        provider: _provider,
        apiBaseUrl: _apiBaseUrlController.text,
        mongoDbUrl: _mongoUrlController.text,
        mongoDatabaseName: MongoDbSyncService.defaultDatabaseName,
        mongoCollectionName: MongoDbSyncService.defaultCollectionName,
      );
      if (!mounted) return;
      setState(() => _status = _provider == SyncDatabaseProvider.local ? 'Local Database is ready.' : 'Connection test passed.');
    } catch (error) {
      if (!mounted) return;
      setState(() => _status = redactSyncSecrets(error.toString().replaceFirst('Bad state: ', '').replaceFirst('Exception: ', '')));
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  Future<void> _saveProviderSettings({bool showStatus = true, bool closePage = false}) async {
    final state = context.read<AppController>();
    await state.configureSyncDatabase(
      provider: _provider,
      apiBaseUrl: _apiBaseUrlController.text,
      mongoDbUrl: _mongoUrlController.text,
      mongoDatabaseName: MongoDbSyncService.defaultDatabaseName,
      mongoCollectionName: MongoDbSyncService.defaultCollectionName,
      tursoDatabaseUrl: _tursoDatabaseUrlController.text,
      tursoAuthToken: _tursoAuthTokenController.text,
    );
    if (!mounted) return;
    if (showStatus) showSnack(context, '${syncDatabaseProviderLabel(_provider)} settings saved.');
    if (closePage) Navigator.pop(context);
  }

  Future<void> _save() async {
    await _saveProviderSettings(closePage: true);
  }

  Future<void> _syncNow() async {
    // Sync downloads the latest data from the selected database provider.
    await _downloadNow();
  }

  Future<void> _uploadNow() async {
    await _saveProviderSettings(showStatus: false);
    final state = context.read<AppController>();
    await state.syncToCloud(force: true);
    if (!mounted) return;
    await _showSyncResult('Local and cloud data merged, then uploaded.');
  }

  Future<void> _downloadNow() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Sync from Database?'),
        content: Text(_provider == SyncDatabaseProvider.mongoDb
            ? 'This downloads the latest snapshot from your MongoDB database and merges it with this device’s local data.'
            : 'This downloads the latest snapshot from the selected database/cloud provider and merges it with this device’s local data.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Sync')),
        ],
      ),
    );
    if (confirmed != true) return;
    await _saveProviderSettings(showStatus: false);
    final state = context.read<AppController>();
    await state.syncFromCloud();
    if (!mounted) return;
    await _showSyncResult('Database data merged with this device.');
  }

  Future<void> _showSyncResult(String successMessage) async {
    final state = context.read<AppController>();
    if (state.cloudSyncApprovalRequired) {
      await _showActivationDialog();
      return;
    }
    showSnack(context, state.cloudSyncError == null ? successMessage : state.cloudSyncError!);
  }

  Future<void> _showActivationDialog() async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Message admin to activate your online sync.'),
        content: const Text('Your Sync ID is waiting for admin approval. After the admin approves it, press Sync again.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
          FilledButton.icon(
            onPressed: () async {
              await launchUrl(Uri.parse(kSyncAdminTelegramUrl), mode: LaunchMode.externalApplication);
            },
            icon: const Icon(Icons.send_rounded),
            label: const Text('Telegram'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppController>();
    final providerLabel = syncDatabaseProviderLabel(_provider);
    return PageScaffold(
      title: providerLabel,
      subtitle: 'Sync method setup',
      child: ResponsiveContent(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ExpressiveCard(
              padding: const EdgeInsets.all(18),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: kSleekAccent.withOpacity(.15),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(syncDatabaseProviderIcon(_provider), color: kSleekAccent),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(providerLabel, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
                        const SizedBox(height: 4),
                        Text(syncDatabaseProviderSubtitle(_provider), style: Theme.of(context).textTheme.bodySmall?.copyWith(color: kSleekMuted, fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            _providerFields(),
            if (_status != null && _status!.trim().isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(_status!, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: kSleekAccent, fontWeight: FontWeight.w800)),
            ],
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _testing || state.cloudSyncBusy ? null : _testConnection,
                    icon: _testing ? const KoinlyInlineLoader(size: 18) : const Icon(Icons.network_check_rounded),
                    label: const Text('Test'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _testing || state.cloudSyncBusy ? null : _save,
                    icon: const Icon(Icons.save_rounded),
                    label: const Text('Save'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            _ProviderSyncActions(
              provider: _provider,
              busy: state.cloudSyncBusy,
              onSync: _syncNow,
              onUpload: _uploadNow,
            ),
          ],
        ),
      ),
    );
  }


  Widget _workerBackedProviderFields(SyncDatabaseProvider provider) {
    final label = syncDatabaseProviderLabel(provider);
    return Column(
      key: ValueKey('${enumName(provider)}-method-page'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
          controller: _apiBaseUrlController,
          decoration: InputDecoration(
            labelText: '$label API URL',
            hintText: 'https://your-koinly-sync-worker.workers.dev',
            prefixIcon: Icon(syncDatabaseProviderIcon(provider)),
          ),
        ),
        const SizedBox(height: 10),
        ExpressiveCard(
          padding: const EdgeInsets.all(16),
          child: Text(
            '$label uses your Koinly sync backend API. Configure that backend to store snapshots in $label, then paste the API URL here. Sync ID and Sync PIN stay on this database method page.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: kSleekMuted, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }

  Widget _hiddenTursoNotice() {
    return ExpressiveCard(
      key: const ValueKey('turso-hidden'),
      padding: const EdgeInsets.all(16),
      child: const Text('Turso Database is hidden for users for now. Choose another database method.'),
    );
  }


  Widget _providerFields() {
    switch (_provider) {
      case SyncDatabaseProvider.local:
        return ExpressiveCard(
          key: const ValueKey('local-method-page'),
          padding: const EdgeInsets.all(16),
          child: const Text('Local Database mode keeps everything in this device SQLite database. Online sync stays disabled and no credentials are required.'),
        );
      case SyncDatabaseProvider.mongoDb:
        return Column(
          key: const ValueKey('mongodb-method-page'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
              controller: _mongoUrlController,
              obscureText: _obscureMongoUrl,
              decoration: InputDecoration(
                labelText: 'MongoDB URL',
                hintText: 'mongodb+srv://user:password@cluster.mongodb.net/koinly',
                prefixIcon: const Icon(Icons.link_rounded),
                suffixIcon: IconButton(
                  onPressed: () => setState(() => _obscureMongoUrl = !_obscureMongoUrl),
                  icon: Icon(_obscureMongoUrl ? Icons.visibility_rounded : Icons.visibility_off_rounded),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Use your own MongoDB database. Koinly stores one latest app snapshot in its internal collection.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: kSleekMuted, fontWeight: FontWeight.w700),
            ),
          ],
        );
      case SyncDatabaseProvider.turso:
        return _hiddenTursoNotice();
      case SyncDatabaseProvider.cloudflareD1:
      case SyncDatabaseProvider.supabase:
      case SyncDatabaseProvider.neonPostgres:
      case SyncDatabaseProvider.firebaseFirestore:
        return _workerBackedProviderFields(_provider);
    }
  }
}

class _ProviderSyncActions extends StatelessWidget {
  const _ProviderSyncActions({
    required this.provider,
    required this.busy,
    required this.onSync,
    required this.onUpload,
  });

  final SyncDatabaseProvider provider;
  final bool busy;
  final VoidCallback onSync;
  final VoidCallback onUpload;

  @override
  Widget build(BuildContext context) {
    final isCloudProvider = provider != SyncDatabaseProvider.local && provider != SyncDatabaseProvider.turso;
    final disabled = busy || !isCloudProvider;
    return ExpressiveCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: kSleekAccent.withOpacity(.15),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: const Icon(Icons.sync_rounded, color: kSleekAccent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Sync actions', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: disabled ? null : onSync,
            icon: busy ? const KoinlyInlineLoader(size: 18) : const Icon(Icons.sync_rounded),
            label: const Text('Sync'),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: disabled ? null : onUpload,
            icon: const Icon(Icons.cloud_upload_rounded),
            label: const Text('Upload Data'),
          ),
        ],
      ),
    );
  }
}

class SyncAdvancedDatabasePopup extends StatefulWidget {
  const SyncAdvancedDatabasePopup({super.key});

  @override
  State<SyncAdvancedDatabasePopup> createState() => _SyncAdvancedDatabasePopupState();
}

class _SyncAdvancedDatabasePopupState extends State<SyncAdvancedDatabasePopup> {
  late SyncDatabaseProvider _provider;
  late final TextEditingController _apiBaseUrlController;
  late final TextEditingController _mongoUrlController;
  late final TextEditingController _mongoDatabaseController;
  late final TextEditingController _mongoCollectionController;
  late final TextEditingController _tursoDatabaseUrlController;
  late final TextEditingController _tursoAuthTokenController;
  bool _obscureMongoUrl = true;
  bool _testing = false;
  String? _status;

  @override
  void initState() {
    super.initState();
    final state = context.read<AppController>();
    _provider = state.syncDatabaseProvider == SyncDatabaseProvider.turso ? SyncDatabaseProvider.local : state.syncDatabaseProvider;
    _apiBaseUrlController = TextEditingController(text: state.cloudSyncApiBaseUrl);
    _mongoUrlController = TextEditingController(text: state.syncMongoDbUrl);
    _mongoDatabaseController = TextEditingController(text: state.syncMongoDatabaseName);
    _mongoCollectionController = TextEditingController(text: state.syncMongoCollectionName);
    _tursoDatabaseUrlController = TextEditingController(text: state.syncTursoDatabaseUrl);
    _tursoAuthTokenController = TextEditingController(text: state.syncTursoAuthToken);
  }

  @override
  void dispose() {
    _apiBaseUrlController.dispose();
    _mongoUrlController.dispose();
    _mongoDatabaseController.dispose();
    _mongoCollectionController.dispose();
    _tursoDatabaseUrlController.dispose();
    _tursoAuthTokenController.dispose();
    super.dispose();
  }

  Future<void> _testConnection() async {
    final state = context.read<AppController>();
    setState(() {
      _testing = true;
      _status = null;
    });
    try {
      await state.testSyncDatabaseConnection(
        provider: _provider,
        apiBaseUrl: _apiBaseUrlController.text,
        mongoDbUrl: _mongoUrlController.text,
        mongoDatabaseName: MongoDbSyncService.defaultDatabaseName,
        mongoCollectionName: MongoDbSyncService.defaultCollectionName,
      );
      if (!mounted) return;
      setState(() => _status = _provider == SyncDatabaseProvider.local ? 'Local Database is ready.' : 'Connection test passed.');
    } catch (error) {
      if (!mounted) return;
      setState(() => _status = redactSyncSecrets(error.toString().replaceFirst('Bad state: ', '').replaceFirst('Exception: ', '')));
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  Future<void> _save() async {
    final state = context.read<AppController>();
    await state.configureSyncDatabase(
      provider: _provider,
      apiBaseUrl: _apiBaseUrlController.text,
      mongoDbUrl: _mongoUrlController.text,
      mongoDatabaseName: MongoDbSyncService.defaultDatabaseName,
      mongoCollectionName: MongoDbSyncService.defaultCollectionName,
      tursoDatabaseUrl: _tursoDatabaseUrlController.text,
      tursoAuthToken: _tursoAuthTokenController.text,
    );
    if (!mounted) return;
    showSnack(context, 'Advanced sync database settings saved.');
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      child: KoinlyPopupContent(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(color: kSleekAccent.withOpacity(.14), borderRadius: BorderRadius.circular(16)),
                  child: const Icon(Icons.tune_rounded, color: kSleekAccent),
                ),
                const SizedBox(width: 12),
                Expanded(child: Text('Advanced sync database', style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900))),
                IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded)),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              'Choose where Koinly stores online sync snapshots. Credentials are saved with platform secure storage and are not included in backups.',
              style: theme.textTheme.bodySmall?.copyWith(color: kSleekMuted, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 16),
            ...userSyncDatabaseProviders.map((provider) => _ProviderChoiceCard(
                  provider: provider,
                  selected: _provider == provider,
                  onTap: () => setState(() => _provider = provider),
                )),
            const SizedBox(height: 10),
            AnimatedSwitcher(
              duration: AppMotion.medium,
              switchInCurve: AppMotion.emphasized,
              switchOutCurve: AppMotion.emphasizedAccelerate,
              child: _providerFields(),
            ),
            if (_status != null && _status!.trim().isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(_status!, style: theme.textTheme.bodySmall?.copyWith(color: kSleekAccent, fontWeight: FontWeight.w800)),
            ],
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _testing ? null : _testConnection,
                    icon: _testing ? const KoinlyInlineLoader(size: 18) : const Icon(Icons.network_check_rounded),
                    label: const Text('Test Connection'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _testing ? null : _save,
                    icon: const Icon(Icons.save_rounded),
                    label: const Text('Save'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }


  Widget _workerBackedProviderFields(SyncDatabaseProvider provider) {
    final label = syncDatabaseProviderLabel(provider);
    return Column(
      key: ValueKey('${enumName(provider)}-advanced'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
          controller: _apiBaseUrlController,
          decoration: InputDecoration(
            labelText: '$label API URL',
            hintText: 'https://your-koinly-sync-worker.workers.dev',
            prefixIcon: Icon(syncDatabaseProviderIcon(provider)),
          ),
        ),
        const SizedBox(height: 10),
        ExpressiveCard(
          padding: const EdgeInsets.all(16),
          child: Text(
            '$label uses your Koinly sync backend API. Configure that backend to store snapshots in $label, then paste the API URL here. Sync ID and Sync PIN stay on this database method page.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: kSleekMuted, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }

  Widget _hiddenTursoNotice() {
    return ExpressiveCard(
      key: const ValueKey('turso-hidden-advanced'),
      padding: const EdgeInsets.all(16),
      child: const Text('Turso Database is hidden for users for now. Choose another database method.'),
    );
  }

  Widget _providerFields() {
    switch (_provider) {
      case SyncDatabaseProvider.local:
        return ExpressiveCard(
          key: const ValueKey('local'),
          padding: const EdgeInsets.all(16),
          child: const Text('Local Database mode keeps everything in this device SQLite database. Online sync stays disabled and no credentials are required.'),
        );
      case SyncDatabaseProvider.mongoDb:
        return Column(
          key: const ValueKey('mongodb'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
              controller: _mongoUrlController,
              obscureText: _obscureMongoUrl,
              decoration: InputDecoration(
                labelText: 'MongoDB URL',
                hintText: 'mongodb+srv://user:password@cluster.mongodb.net/koinly',
                prefixIcon: const Icon(Icons.link_rounded),
                suffixIcon: IconButton(
                  onPressed: () => setState(() => _obscureMongoUrl = !_obscureMongoUrl),
                  icon: Icon(_obscureMongoUrl ? Icons.visibility_rounded : Icons.visibility_off_rounded),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Use your own MongoDB database. Koinly stores one latest app snapshot in its internal collection.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: kSleekMuted, fontWeight: FontWeight.w700),
            ),
          ],
        );
      case SyncDatabaseProvider.turso:
        return _hiddenTursoNotice();
      case SyncDatabaseProvider.cloudflareD1:
      case SyncDatabaseProvider.supabase:
      case SyncDatabaseProvider.neonPostgres:
      case SyncDatabaseProvider.firebaseFirestore:
        return _workerBackedProviderFields(_provider);
    }
  }
}

class _ProviderChoiceCard extends StatelessWidget {
  const _ProviderChoiceCard({required this.provider, required this.selected, required this.onTap});

  final SyncDatabaseProvider provider;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: MotionInkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: AnimatedContainer(
          duration: AppMotion.fast,
          curve: AppMotion.emphasized,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: selected ? kSleekAccent.withOpacity(.16) : scheme.surfaceContainerHighest.withOpacity(.34),
            borderRadius: BorderRadius.circular(selected ? 28 : 22),
            border: Border.all(color: selected ? kSleekAccent.withOpacity(.75) : scheme.outline.withOpacity(.18), width: selected ? 1.5 : 1),
          ),
          child: Row(
            children: [
              Icon(syncDatabaseProviderIcon(provider), color: selected ? kSleekAccent : scheme.onSurfaceVariant),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(syncDatabaseProviderLabel(provider), style: const TextStyle(fontWeight: FontWeight.w900)),
                    const SizedBox(height: 3),
                    Text(syncDatabaseProviderSubtitle(provider), style: Theme.of(context).textTheme.bodySmall?.copyWith(color: kSleekMuted, fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
              Icon(selected ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded, color: selected ? kSleekAccent : scheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> showThemeDialog(BuildContext context) async {
  final state = context.read<AppController>();
  final selectedId = await showAppleWheelSelectionSheet(
    context,
    title: 'Choose Theme',
    selectedId: enumName(state.themePreference),
    options: ThemePreference.values.map(optionFromThemePreference).toList(),
  );
  if (selectedId == null) return;
  final selected = ThemePreference.values.firstWhere(
    (theme) => enumName(theme) == selectedId,
    orElse: () => state.themePreference,
  );
  await state.saveTheme(selected);
}

SelectionOption optionFromThemePreference(ThemePreference theme) {
  switch (theme) {
    case ThemePreference.system:
      return const SelectionOption(
        id: 'system',
        title: 'System Default',
        subtitle: 'Follow device setting',
        iconName: 'theme_system',
        iconColor: '#A6E3A1',
      );
    case ThemePreference.light:
      return const SelectionOption(
        id: 'light',
        title: 'Light',
        subtitle: 'Bright interface',
        iconName: 'theme_light',
        iconColor: '#FBC879',
      );
    case ThemePreference.dark:
      return const SelectionOption(
        id: 'dark',
        title: 'Dark',
        subtitle: 'Low-light interface',
        iconName: 'theme_dark',
        iconColor: '#B4A5FF',
      );
    case ThemePreference.batterySaver:
      return const SelectionOption(
        id: 'batterySaver',
        title: 'Battery Saver / System',
        subtitle: 'Use system behavior',
        iconName: 'theme_battery',
        iconColor: kSleekAccentHex,
      );
  }
}

String _themeLabel(ThemePreference t) {
  switch (t) {
    case ThemePreference.system: return 'System Default';
    case ThemePreference.light: return 'Light';
    case ThemePreference.dark: return 'Dark';
    case ThemePreference.batterySaver: return 'Battery Saver / System';
  }
}

String _dateRangeLabel(DateRangeType type) {
  switch (type) {
    case DateRangeType.today: return 'Today';
    case DateRangeType.thisWeek: return 'This Week';
    case DateRangeType.thisMonth: return 'This Month';
    case DateRangeType.thisYear: return 'This Year';
    case DateRangeType.allTime: return 'All Time';
    case DateRangeType.custom: return 'Custom';
  }
}

void showCurrencySheet(BuildContext context) {
  final state = context.read<AppController>();
  showKoinlyPopup<void>(
    context,
    maxWidth: 560,
    maxHeight: 720,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(14, 18, 14, 14),
      child: KoinlyPopupContent(
        child: CurrencyForm(initialSymbol: state.currencySymbol, initialCode: state.currencyCode, initialPosition: state.currencyPosition, initialSeparators: state.useSeparators, closeAfterSave: true),
      ),
    ),
  );
}

class CurrencyForm extends StatefulWidget {
  const CurrencyForm({super.key, required this.initialSymbol, required this.initialCode, required this.initialPosition, required this.initialSeparators, this.closeAfterSave = false});
  final String initialSymbol;
  final String initialCode;
  final CurrencyPosition initialPosition;
  final bool initialSeparators;
  final bool closeAfterSave;

  @override
  State<CurrencyForm> createState() => _CurrencyFormState();
}

class _CurrencyFormState extends State<CurrencyForm> {
  late TextEditingController symbol;
  late TextEditingController code;
  late CurrencyPosition position;
  late bool separators;
  static const countries = <List<String>>[
    ["Afghanistan", "؋", "AFN"],
    ["Albania", "L", "ALL"],
    ["Algeria", "دج", "DZD"],
    ["Angola", "Kz", "AOA"],
    ["Argentina", "\$", "ARS"],
    ["Armenia", "֏", "AMD"],
    ["Aruba", "ƒ", "AWG"],
    ["Australia", "\$", "AUD"],
    ["Azerbaijan", "₼", "AZN"],
    ["Bahamas", "\$", "BSD"],
    ["Bahrain", ".د.ب", "BHD"],
    ["Bangladesh", "৳", "BDT"],
    ["Barbados", "\$", "BBD"],
    ["Belarus", "Br", "BYN"],
    ["Belize", "\$", "BZD"],
    ["Bermuda", "\$", "BMD"],
    ["Bhutan", "Nu.", "BTN"],
    ["Bolivia", "Bs.", "BOB"],
    ["Bosnia and Herzegovina", "KM", "BAM"],
    ["Botswana", "P", "BWP"],
    ["Brazil", "R\$", "BRL"],
    ["Brunei", "\$", "BND"],
    ["Bulgaria", "лв", "BGN"],
    ["Burundi", "FBu", "BIF"],
    ["Cambodia", "៛", "KHR"],
    ["Canada", "\$", "CAD"],
    ["Cape Verde", "\$", "CVE"],
    ["Cayman Islands", "\$", "KYD"],
    ["Chile", "\$", "CLP"],
    ["China", "¥", "CNY"],
    ["Colombia", "\$", "COP"],
    ["Comoros", "CF", "KMF"],
    ["Costa Rica", "₡", "CRC"],
    ["Croatia", "€", "EUR"],
    ["Cuba", "\$", "CUP"],
    ["Czech Republic", "Kč", "CZK"],
    ["Denmark", "kr", "DKK"],
    ["Djibouti", "Fdj", "DJF"],
    ["Dominican Republic", "RD\$", "DOP"],
    ["DR Congo", "FC", "CDF"],
    ["East Caribbean", "EC\$", "XCD"],
    ["Egypt", "E£", "EGP"],
    ["El Salvador", "\$", "USD"],
    ["Eritrea", "Nfk", "ERN"],
    ["Eswatini", "E", "SZL"],
    ["Ethiopia", "Br", "ETB"],
    ["Euro Area", "€", "EUR"],
    ["Falkland Islands", "£", "FKP"],
    ["Fiji", "\$", "FJD"],
    ["Gambia", "D", "GMD"],
    ["Georgia", "₾", "GEL"],
    ["Ghana", "₵", "GHS"],
    ["Gibraltar", "£", "GIP"],
    ["Guatemala", "Q", "GTQ"],
    ["Guernsey", "£", "GGP"],
    ["Guinea", "FG", "GNF"],
    ["Guyana", "\$", "GYD"],
    ["Haiti", "G", "HTG"],
    ["Honduras", "L", "HNL"],
    ["Hong Kong", "\$", "HKD"],
    ["Hungary", "Ft", "HUF"],
    ["Iceland", "kr", "ISK"],
    ["India", "₹", "INR"],
    ["Indonesia", "Rp", "IDR"],
    ["Iran", "﷼", "IRR"],
    ["Iraq", "ع.د", "IQD"],
    ["Isle of Man", "£", "IMP"],
    ["Israel", "₪", "ILS"],
    ["Jamaica", "J\$", "JMD"],
    ["Japan", "¥", "JPY"],
    ["Jersey", "£", "JEP"],
    ["Jordan", "د.ا", "JOD"],
    ["Kazakhstan", "₸", "KZT"],
    ["Kenya", "KSh", "KES"],
    ["Kuwait", "د.ك", "KWD"],
    ["Kyrgyzstan", "с", "KGS"],
    ["Laos", "₭", "LAK"],
    ["Lebanon", "ل.ل", "LBP"],
    ["Lesotho", "L", "LSL"],
    ["Liberia", "\$", "LRD"],
    ["Libya", "ل.د", "LYD"],
    ["Macau", "MOP\$", "MOP"],
    ["Madagascar", "Ar", "MGA"],
    ["Malawi", "MK", "MWK"],
    ["Malaysia", "RM", "MYR"],
    ["Maldives", "Rf", "MVR"],
    ["Mauritania", "UM", "MRU"],
    ["Mauritius", "₨", "MUR"],
    ["Mexico", "\$", "MXN"],
    ["Moldova", "L", "MDL"],
    ["Mongolia", "₮", "MNT"],
    ["Morocco", "د.م.", "MAD"],
    ["Mozambique", "MT", "MZN"],
    ["Myanmar", "K", "MMK"],
    ["Namibia", "\$", "NAD"],
    ["Nepal", "₨", "NPR"],
    ["Netherlands Antilles", "ƒ", "ANG"],
    ["New Zealand", "\$", "NZD"],
    ["Nicaragua", "C\$", "NIO"],
    ["Nigeria", "₦", "NGN"],
    ["North Macedonia", "ден", "MKD"],
    ["Norway", "kr", "NOK"],
    ["Oman", "ر.ع.", "OMR"],
    ["Pakistan", "₨", "PKR"],
    ["Panama", "B/.", "PAB"],
    ["Papua New Guinea", "K", "PGK"],
    ["Paraguay", "₲", "PYG"],
    ["Peru", "S/", "PEN"],
    ["Philippines", "₱", "PHP"],
    ["Poland", "zł", "PLN"],
    ["Qatar", "ر.ق", "QAR"],
    ["Romania", "lei", "RON"],
    ["Russia", "₽", "RUB"],
    ["Rwanda", "FRw", "RWF"],
    ["Saint Helena", "£", "SHP"],
    ["Samoa", "T", "WST"],
    ["Saudi Arabia", "﷼", "SAR"],
    ["Serbia", "дин", "RSD"],
    ["Seychelles", "₨", "SCR"],
    ["Sierra Leone", "Le", "SLE"],
    ["Singapore", "\$", "SGD"],
    ["Solomon Islands", "\$", "SBD"],
    ["Somalia", "Sh", "SOS"],
    ["South Africa", "R", "ZAR"],
    ["South Korea", "₩", "KRW"],
    ["South Sudan", "£", "SSP"],
    ["Sri Lanka", "₨", "LKR"],
    ["Sudan", "ج.س.", "SDG"],
    ["Suriname", "\$", "SRD"],
    ["Sweden", "kr", "SEK"],
    ["Switzerland", "CHF", "CHF"],
    ["Syria", "£", "SYP"],
    ["São Tomé and Príncipe", "Db", "STN"],
    ["Taiwan", "NT\$", "TWD"],
    ["Tajikistan", "ЅМ", "TJS"],
    ["Tanzania", "TSh", "TZS"],
    ["Thailand", "฿", "THB"],
    ["Tonga", "T\$", "TOP"],
    ["Trinidad and Tobago", "TT\$", "TTD"],
    ["Tunisia", "د.ت", "TND"],
    ["Turkey", "₺", "TRY"],
    ["Turkmenistan", "m", "TMT"],
    ["Uganda", "USh", "UGX"],
    ["Ukraine", "₴", "UAH"],
    ["United Arab Emirates", "د.إ", "AED"],
    ["United Kingdom", "£", "GBP"],
    ["United States", "\$", "USD"],
    ["Uruguay", "\$U", "UYU"],
    ["Uzbekistan", "soʻm", "UZS"],
    ["Vanuatu", "VT", "VUV"],
    ["Venezuela", "Bs.", "VES"],
    ["Vietnam", "₫", "VND"],
    ["Yemen", "﷼", "YER"],
    ["Zambia", "ZK", "ZMW"],
    ["Zimbabwe", "\$", "ZWL"],
  ];

  @override
  void initState() {
    super.initState();
    symbol = TextEditingController(text: widget.initialSymbol);
    code = TextEditingController(text: widget.initialCode);
    position = widget.initialPosition;
    separators = widget.initialSeparators;
    symbol.addListener(_persistCurrency);
    code.addListener(_persistCurrency);
  }

  @override
  void dispose() {
    symbol.removeListener(_persistCurrency);
    code.removeListener(_persistCurrency);
    symbol.dispose();
    code.dispose();
    super.dispose();
  }

  void _persistCurrency() {
    if (!mounted) return;
    context.read<AppController>().saveCurrency(
      symbol: symbol.text.trim().isEmpty ? '৳' : symbol.text.trim(),
      code: code.text.trim().isEmpty ? 'BDT' : code.text.trim().toUpperCase(),
      position: position,
      separators: separators,
    );
  }

  List<String> get _selectedCurrency {
    final exact = countries.where((c) => c[1] == symbol.text && c[2] == code.text).toList();
    if (exact.isNotEmpty) return exact.first;
    final byCode = countries.where((c) => c[2] == code.text).toList();
    if (byCode.isNotEmpty) return byCode.first;
    return ['Custom currency', symbol.text.trim().isEmpty ? '৳' : symbol.text.trim(), code.text.trim().isEmpty ? 'BDT' : code.text.trim()];
  }

  Future<void> _openCurrencyPicker() async {
    final selected = await showCurrencyWheelPickerSheet(
      context,
      countries: countries,
      selectedCode: code.text,
      selectedSymbol: symbol.text,
    );
    if (selected == null || !mounted) return;
    setState(() {
      symbol.text = selected[1];
      code.text = selected[2];
    });
    _persistCurrency();
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selectedCurrency;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.closeAfterSave) ...[
          Text('Currency customization', textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900)),
          const SizedBox(height: 14),
        ],
        CurrencyCustomizationButton(
          country: selected[0],
          symbol: selected[1],
          code: selected[2],
          onTap: _openCurrencyPicker,
        ),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(child: TextField(
            onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
            controller: symbol, decoration: const InputDecoration(labelText: 'Symbol'))),
          const SizedBox(width: 10),
          Expanded(child: TextField(
            onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
            controller: code, textCapitalization: TextCapitalization.characters, decoration: const InputDecoration(labelText: 'Code'))),
        ]),
        const SizedBox(height: 12),
        SleekPillSelector<CurrencyPosition>(
          options: const [
            SleekPillOption(value: CurrencyPosition.prefix, label: 'Prefix'),
            SleekPillOption(value: CurrencyPosition.suffix, label: 'Suffix'),
          ],
          selected: position,
          onChanged: (v) {
            setState(() => position = v);
            _persistCurrency();
          },
        ),
        SwitchListTile(
          value: separators,
          onChanged: (v) {
            setState(() => separators = v);
            _persistCurrency();
          },
          title: const Text('Use comma separator'),
          contentPadding: EdgeInsets.zero,
        ),
      ],
    );
  }
}

class CurrencyCustomizationButton extends StatelessWidget {
  const CurrencyCustomizationButton({
    super.key,
    required this.country,
    required this.symbol,
    required this.code,
    required this.onTap,
  });

  final String country;
  final String symbol;
  final String code;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerHighest.withOpacity(.52),
      borderRadius: BorderRadius.circular(22),
      child: MotionInkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: Theme.of(context).colorScheme.outline.withOpacity(.28), width: .9),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: kSleekAccent.withOpacity(.16),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: kSleekAccent.withOpacity(.24)),
                ),
                child: const Icon(Icons.payments_rounded, color: kSleekAccent),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Currency customization', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
                    const SizedBox(height: 3),
                    Text(
                      '$country • $symbol • $code',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: kSleekMuted, fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.chevron_right_rounded),
            ],
          ),
        ),
      ),
    );
  }
}

Future<List<String>?> showCurrencyWheelPickerSheet(
  BuildContext context, {
  required List<List<String>> countries,
  required String selectedCode,
  required String selectedSymbol,
}) async {
  var search = '';

  List<List<String>> filteredCountries() {
    final query = search.trim().toLowerCase();
    final filtered = query.isEmpty
        ? countries.toList()
        : countries.where((c) => c.join(' ').toLowerCase().contains(query)).toList();
    filtered.sort((a, b) => a[0].compareTo(b[0]));
    return filtered;
  }

  final initialCountries = filteredCountries();
  var selectedIndex = initialCountries.indexWhere((c) => c[2] == selectedCode && c[1] == selectedSymbol);
  if (selectedIndex < 0) selectedIndex = initialCountries.indexWhere((c) => c[2] == selectedCode);
  if (selectedIndex < 0) selectedIndex = 0;

  const rowExtent = 72.0;
  final initialListHeight = math.min(288.0, math.max(rowExtent, initialCountries.length * rowExtent));
  final initialMaxScrollExtent = math.max(0.0, (initialCountries.length * rowExtent) - initialListHeight);
  final listController = ScrollController(
    initialScrollOffset: math.min(
      initialMaxScrollExtent,
      math.max(0.0, (selectedIndex - 1) * rowExtent),
    ),
  );

  final result = await showKoinlyPopup<List<String>>(
    context,
    maxWidth: 560,
    maxHeight: 660,
    child: StatefulBuilder(
      builder: (dialogContext, setModalState) {
        final filtered = filteredCountries();
        if (filtered.isNotEmpty && selectedIndex >= filtered.length) selectedIndex = 0;
        final safeIndex = filtered.isEmpty
            ? 0
            : selectedIndex < 0
                ? 0
                : selectedIndex >= filtered.length
                    ? filtered.length - 1
                    : selectedIndex;
        final selected = filtered.isEmpty ? null : filtered[safeIndex];
        final listHeight = filtered.isEmpty
            ? 96.0
            : math.min(288.0, math.max(rowExtent, filtered.length * rowExtent));
        final dark = Theme.of(dialogContext).brightness == Brightness.dark;
        final innerColor = dark ? kSleekSurfaceLow : kSleekLightBackground;
        final innerBorderColor = dark ? kSleekOutlineVariant : kSleekLightOutlineVariant;
        final handleColor = dark ? const Color(0xFF466057) : const Color(0xFFB7C9BF);

        return KoinlyPopupContent(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 44,
                height: 5,
                decoration: BoxDecoration(color: handleColor, borderRadius: BorderRadius.circular(999)),
              ),
              const SizedBox(height: 18),
              Text(
                'Choose currency',
                textAlign: TextAlign.center,
                style: Theme.of(dialogContext).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 12),
              TextField(
                onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
                autofocus: false,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search_rounded),
                  hintText: 'Search countries or currency code',
                ),
                onChanged: (value) {
                  setModalState(() {
                    search = value;
                    selectedIndex = 0;
                  });
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (listController.hasClients) listController.jumpTo(0);
                  });
                },
              ),
              const SizedBox(height: 12),
              AnimatedContainer(
                duration: AppMotion.fast,
                curve: AppMotion.emphasized,
                height: listHeight,
                decoration: BoxDecoration(
                  color: innerColor,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: innerBorderColor),
                ),
                clipBehavior: Clip.antiAlias,
                child: filtered.isEmpty
                    ? Center(
                        child: Text(
                          'No currency found',
                          style: Theme.of(dialogContext).textTheme.bodyLarge?.copyWith(color: kSleekMuted, fontWeight: FontWeight.w700),
                        ),
                      )
                    : Scrollbar(
                        controller: listController,
                        thumbVisibility: kIsDesktopApp && filtered.length > 4,
                        child: ListView.builder(
                          controller: listController,
                          itemExtent: rowExtent,
                          padding: EdgeInsets.zero,
                          physics: optimizedScrollPhysics(dialogContext),
                          itemCount: filtered.length,
                          itemBuilder: (context, index) {
                            final c = filtered[index];
                            final isSelected = index == safeIndex;
                            return Material(
                              color: Colors.transparent,
                              child: MotionInkWell(
                                onTap: () => setModalState(() => selectedIndex = index),
                                child: _CurrencyWheelRow(country: c, selected: isSelected),
                              ),
                            );
                          },
                        ),
                      ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: FilledButton(
                      onPressed: selected == null ? null : () => Navigator.pop(dialogContext, selected),
                      child: const Text('Done'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    ),
  );

  listController.dispose();
  return result;
}

class _CurrencyWheelRow extends StatelessWidget {
  const _CurrencyWheelRow({required this.country, required this.selected});

  final List<String> country;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: AppMotion.fast,
      curve: AppMotion.emphasized,
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: selected ? kSleekAccent.withOpacity(.10) : Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: selected ? kSleekAccent.withOpacity(.52) : Colors.transparent,
          width: 1.1,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _CurrencySymbolBubble(symbol: country[1], selected: selected),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  country[0],
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: selected ? scheme.onSurface : scheme.onSurface.withOpacity(.76),
                      ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${country[1]} • ${country[2]}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: selected ? kSleekMuted : kSleekMuted.withOpacity(.72),
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ],
            ),
          ),
          if (selected) ...[
            const SizedBox(width: 10),
            const Icon(Icons.check_rounded, color: kSleekAccent, size: 22),
          ],
        ],
      ),
    );
  }
}

class _CurrencySymbolBubble extends StatelessWidget {
  const _CurrencySymbolBubble({required this.symbol, required this.selected});

  final String symbol;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: kSleekAccent.withOpacity(selected ? .20 : .12),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: kSleekAccent.withOpacity(selected ? .36 : .18), width: selected ? 1.3 : 1),
      ),
      alignment: Alignment.center,
      child: Text(
        symbol,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: kSleekAccent,
              fontWeight: FontWeight.w900,
            ),
      ),
    );
  }
}


void showReminderSheet(BuildContext context) {
  showKoinlyPopup<void>(context, maxWidth: 520, maxHeight: 520, child: const ReminderSheet());
}

class ReminderSheet extends StatefulWidget {
  const ReminderSheet({super.key});

  @override
  State<ReminderSheet> createState() => _ReminderSheetState();
}

class _ReminderSheetState extends State<ReminderSheet> {
  late bool enabled;
  late TimeOfDay time;

  @override
  void initState() {
    super.initState();
    final state = context.read<AppController>();
    enabled = state.reminderEnabled;
    time = state.reminderTime;
  }

  @override
  Widget build(BuildContext context) {
    final state = context.read<AppController>();
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 22, 18, 24),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Daily reminder', textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900)),
        SwitchListTile(value: enabled, onChanged: (v) => setState(() => enabled = v), title: const Text('Enable reminder'), subtitle: const Text('Notification text: “Don’t forget to record your expenses”')),
        OutlinedButton.icon(onPressed: () async { final t = await pickTime(context, time); if (t != null) setState(() => time = t); }, icon: const Icon(Icons.schedule_rounded), label: Text(time.format(context))),
        const SizedBox(height: 12),
        FilledButton(onPressed: () async { await state.setReminder(enabled, time); if (context.mounted) Navigator.pop(context); }, child: const Text('Save reminder')),
      ]),
    );
  }
}

void showAutomaticBackupSheet(BuildContext context) {
  showKoinlyPopup<void>(
    context,
    maxWidth: 560,
    maxHeight: 760,
    barrierDismissible: false,
    child: const _AutomaticBackupSheet(),
  );
}

class _AutomaticBackupSheet extends StatefulWidget {
  const _AutomaticBackupSheet();

  @override
  State<_AutomaticBackupSheet> createState() => _AutomaticBackupSheetState();
}

class _AutomaticBackupSheetState extends State<_AutomaticBackupSheet> {
  late bool enabled;
  late AutoBackupFrequency frequency;
  late TimeOfDay time;
  late int weekday;
  late int monthDay;
  late bool deleteOlderBackups;
  late String directoryPath;
  late String directoryUri;
  late String directoryLabel;
  bool saving = false;

  static const _weekdayLabels = <int, String>{
    DateTime.monday: 'Monday',
    DateTime.tuesday: 'Tuesday',
    DateTime.wednesday: 'Wednesday',
    DateTime.thursday: 'Thursday',
    DateTime.friday: 'Friday',
    DateTime.saturday: 'Saturday',
    DateTime.sunday: 'Sunday',
  };

  @override
  void initState() {
    super.initState();
    final state = context.read<AppController>();
    enabled = state.autoBackupEnabled;
    frequency = state.autoBackupFrequency;
    time = state.autoBackupTime;
    weekday = state.autoBackupWeekday;
    monthDay = state.autoBackupMonthDay;
    deleteOlderBackups = state.autoBackupDeleteOlder;
    directoryPath = state.autoBackupDirectoryPath;
    directoryUri = state.autoBackupDirectoryUri;
    directoryLabel = state.autoBackupDirectoryLabel;
  }

  Future<void> _chooseDirectory() async {
    final selected = await BackupService.pickAutomaticBackupDirectory();
    if (selected != null && mounted) {
      setState(() {
        directoryPath = selected.path;
        directoryUri = selected.uri;
        directoryLabel = selected.label;
      });
    }
  }

  Future<void> _save() async {
    if (saving) return;
    if (enabled && directoryPath.trim().isEmpty && directoryUri.trim().isEmpty) {
      showSnack(context, 'Choose a backup folder first.');
      return;
    }
    setState(() => saving = true);
    final state = context.read<AppController>();
    await state.setAutomaticBackupSettings(
      enabled: enabled,
      frequency: frequency,
      time: time,
      weekday: weekday,
      monthDay: monthDay,
      deleteOlderBackups: deleteOlderBackups,
      directoryPath: directoryPath,
      directoryUri: directoryUri,
      directoryLabel: directoryLabel,
    );
    if (!mounted) return;
    if (enabled && state.autoBackupError != null && state.autoBackupError!.isNotEmpty) {
      setState(() => saving = false);
      showSnack(context, 'Automatic backup could not write to the selected location.');
      return;
    }
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppController>();
    final locationText = directoryUri.trim().isNotEmpty
        ? (directoryLabel.trim().isEmpty ? 'Koinly/Backup' : directoryLabel.trim())
        : (directoryPath.trim().isEmpty ? 'No backup folder selected' : directoryPath.trim());
    return KoinlyPopupContent(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Automatic local backup',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
                ),
              ),
              IconButton(onPressed: saving ? null : () => Navigator.pop(context), icon: const Icon(Icons.close_rounded)),
            ],
          ),
          const SizedBox(height: 4),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: enabled,
            onChanged: saving ? null : (value) => setState(() => enabled = value),
            title: const Text('Back up automatically', style: TextStyle(fontWeight: FontWeight.w900)),
            subtitle: const Text('Creates encrypted .koinlybackup files on this device.'),
          ),
          const SectionHeader('When to back up'),
          SleekPillSelector<AutoBackupFrequency>(
            options: const [
              SleekPillOption(value: AutoBackupFrequency.daily, label: 'Daily'),
              SleekPillOption(value: AutoBackupFrequency.weekly, label: 'Weekly'),
              SleekPillOption(value: AutoBackupFrequency.monthly, label: 'Monthly'),
            ],
            selected: frequency,
            onChanged: (value) {
              if (!saving) setState(() => frequency = value);
            },
          ),
          const SizedBox(height: 10),
          if (frequency == AutoBackupFrequency.weekly)
            DropdownButtonFormField<int>(
              value: weekday,
              decoration: const InputDecoration(labelText: 'Backup day'),
              items: _weekdayLabels.entries
                  .map((entry) => DropdownMenuItem<int>(value: entry.key, child: Text(entry.value)))
                  .toList(),
              onChanged: saving
                  ? null
                  : (value) {
                      if (value != null) setState(() => weekday = value);
                    },
            ),
          if (frequency == AutoBackupFrequency.monthly)
            DropdownButtonFormField<int>(
              value: monthDay,
              decoration: const InputDecoration(labelText: 'Day of month'),
              items: List<DropdownMenuItem<int>>.generate(
                28,
                (index) => DropdownMenuItem<int>(value: index + 1, child: Text('Day ${index + 1}')),
              ),
              onChanged: saving
                  ? null
                  : (value) {
                      if (value != null) setState(() => monthDay = value);
                    },
            ),
          if (frequency != AutoBackupFrequency.daily) const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: saving
                ? null
                : () async {
                    final selected = await pickTime(context, time);
                    if (selected != null && mounted) setState(() => time = selected);
                  },
            icon: const Icon(Icons.schedule_rounded),
            label: Text('Time · ${time.format(context)}'),
          ),
          const SectionHeader('Backup history'),
          ExpressiveCard(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: SwitchListTile(
              value: deleteOlderBackups,
              onChanged: saving ? null : (value) => setState(() => deleteOlderBackups = value),
              title: const Text('Delete older automatic backups', style: TextStyle(fontWeight: FontWeight.w900)),
              subtitle: const Text(
                'When on, Koinly deletes previous automatic backups after a new one is saved, so only the latest automatic backup remains. Turn it off to keep backup history.',
              ),
            ),
          ),
          const SectionHeader('Where to back up'),
          ExpressiveCard(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.folder_rounded, color: kSleekAccent),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        locationText,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: saving ? null : _chooseDirectory,
                  icon: const Icon(Icons.drive_folder_upload_rounded),
                  label: const Text('Choose folder'),
                ),
                const SizedBox(height: 10),
                Text(
                  Platform.isAndroid
                      ? 'Choose a parent location once. Koinly creates and uses Koinly/Backup there, with persistent Android folder access for scheduled backups.'
                      : 'Choose a parent location. Koinly creates and uses a Koinly/Backup folder there.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: kSleekMuted, fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(
            state.lastAutoBackupLabel,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: kSleekMuted, fontWeight: FontWeight.w800),
          ),
          if (state.autoBackupEnabled) ...[
            const SizedBox(height: 3),
            Text(
              state.nextAutoBackupLabel,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: kSleekMuted, fontWeight: FontWeight.w700),
            ),
          ],
          if (state.autoBackupError != null && state.autoBackupError!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Last automatic backup failed: ${state.autoBackupError}',
              style: const TextStyle(color: kSleekExpense, fontWeight: FontWeight.w800),
            ),
          ],
          const SizedBox(height: 10),
          Text(
            'If Koinly is closed at the scheduled time, the missed backup is created the next time the app opens or resumes.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: kSleekMuted, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(child: OutlinedButton(onPressed: saving ? null : () => Navigator.pop(context), child: const Text('Cancel'))),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: FilledButton(
                  onPressed: saving ? null : _save,
                  child: Text(saving ? 'Saving...' : 'Save backup settings'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class AdvancedSettingsScreen extends StatelessWidget {
  const AdvancedSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppController>();
    return PageScaffold(
      title: 'Advanced settings',
      child: ResponsiveContent(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        child: Column(children: [
          SettingsTile(icon: Icons.account_balance_wallet_rounded, title: 'Default account', subtitle: state.defaultAccountId == null ? 'Not selected' : state.accountOf(state.defaultAccountId!)?.name ?? 'Unknown', color: kSleekAccentHex, onTap: () => showDefaultSelection(context, 'account')),
          SettingsTile(icon: Icons.north_east_rounded, title: 'Default expense category', subtitle: state.defaultExpenseCategoryId == null ? 'Not selected' : state.categoryOf(state.defaultExpenseCategoryId!)?.name ?? 'Unknown', color: '#FF9F9F', onTap: () => showDefaultSelection(context, 'expense')),
          SettingsTile(icon: Icons.south_west_rounded, title: 'Default income category', subtitle: state.defaultIncomeCategoryId == null ? 'Not selected' : state.categoryOf(state.defaultIncomeCategoryId!)?.name ?? 'Unknown', color: '#A6E3A1', onTap: () => showDefaultSelection(context, 'income')),
          SettingsTile(icon: Icons.swap_vert_rounded, title: 'Account reorder', subtitle: 'Reorder account sequence', color: '#FBC879', onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AccountReorderScreen()))),
          SettingsTile(icon: Icons.backup_rounded, title: 'Backup', color: '#86E3CE', onTap: () => runBackupFlow(context, state)),
          SettingsTile(icon: Icons.history_toggle_off_rounded, title: 'Automatic local backup', subtitle: state.automaticBackupSettingsSummary, color: '#7FE7D4', onTap: () => showAutomaticBackupSheet(context)),
          SettingsTile(icon: Icons.file_open_rounded, title: 'Load backup', subtitle: 'Pick a backup file and merge it with this device', color: '#B4A5FF', onTap: () => runLoadBackupFlow(context, state)),
          SettingsTile(
            icon: Icons.fact_check_rounded,
            title: 'Data health',
            subtitle: state.dataHealthReport?.statusTitle ?? 'Check references, sync backlog, and setup leftovers',
            color: kSleekAccentHex,
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const DataHealthScreen())),
          ),
        ]),
      ),
    );
  }
}

class DataHealthScreen extends StatefulWidget {
  const DataHealthScreen({super.key});

  @override
  State<DataHealthScreen> createState() => _DataHealthScreenState();
}

class _DataHealthScreenState extends State<DataHealthScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<AppController>().checkDataHealth();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppController>();
    final report = state.dataHealthReport;
    final busy = state.dataHealthBusy;
    final statusColor = report == null
        ? kSleekAccent
        : report.hasErrors
            ? kSleekExpense
            : report.hasWarnings
                ? const Color(0xFFFBC879)
                : kSleekIncome;
    return PageScaffold(
      title: 'Data health',
      subtitle: 'Safety checks for local data and sync',
      child: ResponsiveContent(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ExpressiveCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      iconBubble(context, report?.hasErrors == true ? 'warning' : 'check', colorToHex(statusColor), size: 54),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(report?.statusTitle ?? 'Not checked yet', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
                            const SizedBox(height: 4),
                            Text(
                              report == null ? 'Run a quick scan before blaming ghosts in the machine.' : report.statusBody,
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: kSleekMuted, fontWeight: FontWeight.w700),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: busy ? null : () => context.read<AppController>().checkDataHealth(),
                    icon: busy ? const KoinlyInlineLoader(size: 18) : const Icon(Icons.refresh_rounded),
                    label: Text(busy ? 'Checking...' : 'Check again'),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: busy ? null : () => copyDiagnosticsReportFlow(context, context.read<AppController>()),
                          icon: const Icon(Icons.copy_rounded),
                          label: const Text('Copy report'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: busy ? null : () => shareDiagnosticsReportFlow(context, context.read<AppController>()),
                          icon: const Icon(Icons.ios_share_rounded),
                          label: const Text('Share'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (report != null) ...[
              const SectionHeader('Snapshot'),
              Row(
                children: [
                  Expanded(child: MiniMetric('Accounts', '${report.accountCount}', Icons.account_balance_wallet_rounded)),
                  const SizedBox(width: 10),
                  Expanded(child: MiniMetric('Transactions', '${report.transactionCount}', Icons.receipt_long_rounded)),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(child: MiniMetric('Categories', '${report.categoryCount}', Icons.category_rounded)),
                  const SizedBox(width: 10),
                  Expanded(child: MiniMetric('Budgets', '${report.budgetCount}', Icons.savings_rounded)),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(child: MiniMetric('Records', '${report.loanCount}', Icons.currency_exchange_rounded)),
                  const SizedBox(width: 10),
                  Expanded(child: MiniMetric('Repayments', '${report.loanPaymentCount}', Icons.payments_rounded)),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(child: MiniMetric('Pending sync', '${report.pendingSyncOperations}', Icons.cloud_upload_rounded)),
                  const SizedBox(width: 10),
                  Expanded(child: MiniMetric('Sync conflicts', '${report.openSyncConflicts}', Icons.sync_problem_rounded)),
                ],
              ),
              const SectionHeader('Findings'),
              if (report.items.isEmpty)
                const EmptyCard(
                  icon: Icons.verified_rounded,
                  title: 'Everything looks healthy',
                  body: 'No broken references, sync conflicts, or skipped setup leftovers were found.',
                )
              else
                ...report.items.map(
                  (item) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: DataHealthFindingCard(item: item),
                  ),
                ),
              if (report.skippedStarterPlaceholdersVisible) ...[
                const SizedBox(height: 6),
                FilledButton.icon(
                  onPressed: busy
                      ? null
                      : () async {
                          await context.read<AppController>().removeSkippedStarterAccountsFromHealthCheck();
                          if (context.mounted) showSnack(context, 'Untouched starter accounts removed.');
                        },
                  icon: const Icon(Icons.cleaning_services_rounded),
                  label: const Text('Remove skipped starter accounts'),
                ),
              ],
              const SizedBox(height: 12),
              Text(
                'Last checked ${DateFormat('MMM d, yyyy • h:mm a').format(report.checkedAt)}',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: kSleekMuted, fontWeight: FontWeight.w700),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class DataHealthFindingCard extends StatelessWidget {
  const DataHealthFindingCard({super.key, required this.item});

  final DataHealthItem item;

  @override
  Widget build(BuildContext context) {
    final color = switch (item.severity) {
      DataHealthSeverity.error => kSleekExpense,
      DataHealthSeverity.warning => const Color(0xFFFBC879),
      DataHealthSeverity.info => kSleekAccent,
    };
    final icon = switch (item.severity) {
      DataHealthSeverity.error => Icons.error_rounded,
      DataHealthSeverity.warning => Icons.warning_amber_rounded,
      DataHealthSeverity.info => Icons.info_rounded,
    };
    return ExpressiveCard(
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: color.withOpacity(.16),
              borderRadius: BorderRadius.circular(15),
              border: Border.all(color: color.withOpacity(.22)),
            ),
            child: Icon(icon, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
                const SizedBox(height: 4),
                Text(item.body, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: kSleekMuted, fontWeight: FontWeight.w700)),
                if (item.actionLabel != null) ...[
                  const SizedBox(height: 8),
                  Text(item.actionLabel!, style: Theme.of(context).textTheme.labelLarge?.copyWith(color: color, fontWeight: FontWeight.w900)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> showDefaultSelection(BuildContext context, String mode) async {
  final state = context.read<AppController>();

  if (mode == 'account') {
    final selected = await showAppleWheelSelectionSheet(
      context,
      title: 'Choose Default Account',
      selectedId: state.defaultAccountId,
      options: state.accounts.map((account) => optionFromAccount(account, state)).toList(),
      addActionLabel: 'Add account',
      onAdd: () => showAccountEditor(context, allowedTypes: AccountType.values),
    );
    if (selected != null) await state.saveDefaults(accountId: selected);
    return;
  }

  final isIncome = mode == 'income';
  final categories = state.categories
      .where((category) => category.type == (isIncome ? CategoryType.income : CategoryType.expense))
      .toList();

  final selected = await showAppleWheelSelectionSheet(
    context,
    title: isIncome ? 'Choose Default Income Category' : 'Choose Default Expense Category',
    selectedId: isIncome ? state.defaultIncomeCategoryId : state.defaultExpenseCategoryId,
    options: categories.map(optionFromCategory).toList(),
    addActionLabel: 'Add category',
    onAdd: () => showCategoryEditor(
      context,
      initialType: isIncome ? CategoryType.income : CategoryType.expense,
      fixedType: isIncome ? CategoryType.income : CategoryType.expense,
    ),
  );

  if (selected != null) {
    await state.saveDefaults(
      incomeCategoryId: isIncome ? selected : null,
      expenseCategoryId: isIncome ? null : selected,
    );
  }
}

class _AboutLink {
  const _AboutLink(this.label, this.shortLabel, this.icon, this.url);

  final String label;
  final String shortLabel;
  final IconData icon;
  final String url;
}

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  static const links = [
    _AboutLink('Telegram', 'Telegram', Icons.near_me_rounded, 'https://t.me/Ch0wdhury_Siam'),
    _AboutLink('Telegram backup', 'Telegram 2', Icons.send_rounded, 'https://t.me/Chowdhury_Siam'),
    _AboutLink('GitHub', 'GitHub', Icons.code_rounded, 'https://github.com/Chowdhury-Siam/Koinly'),
    _AboutLink('MyAnimeList', 'MAL', Icons.format_list_bulleted_rounded, 'https://myanimelist.net/profile/Siam_Chowdhury'),
    _AboutLink('AniList', 'AniList', Icons.analytics_rounded, 'https://anilist.co/user/SiamChowdhury/'),
    _AboutLink('YouTube', 'YouTube', Icons.play_circle_fill_rounded, 'https://www.youtube.com/@SCS_Otaku'),
    _AboutLink('X / Twitter', 'X', Icons.close_rounded, 'https://x.com/SiamChowdhuryy'),
    _AboutLink('Email', 'Email', Icons.email_rounded, 'mailto:ssiam4235@gmail.com'),
  ];

  @override
  Widget build(BuildContext context) {
    return PageScaffold(
      title: 'About Us',
      child: ResponsiveContent(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ExpressiveCard(
              child: Column(children: [
                const Icon(Icons.account_balance_wallet_rounded, size: 64),
                const SizedBox(height: 12),
                Text('Developed by Siam Chowdhury', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900), textAlign: TextAlign.center),
                const SizedBox(height: 8),
                Text('Version: $appVersion', textAlign: TextAlign.center),
                const SizedBox(height: 16),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 10,
                  runSpacing: 12,
                  children: links.map((link) => _AboutLinkButton(link: link)).toList(),
                ),
              ]),
            ),
            const SectionHeader('Legal'),
            SettingsTile(icon: Icons.privacy_tip_rounded, title: 'Privacy Policy', subtitle: 'Local data-first finance tracker', color: kSleekAccentHex, onTap: () => _showLegal(context, 'Privacy Policy')),
            SettingsTile(icon: Icons.description_rounded, title: 'Terms and conditions', subtitle: 'Usage terms', color: '#A6E3A1', onTap: () => _showLegal(context, 'Terms and conditions')),
            SettingsTile(icon: Icons.balance_rounded, title: 'Open-source licenses', subtitle: 'Apache License 2.0 and Flutter package notices', color: '#FBC879', onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const KoinlyLicenseScreen()))),
          ],
        ),
      ),
    );
  }

  void _showLegal(BuildContext context, String title) {
    showDialog(context: context, builder: (_) => AlertDialog(title: Text(title), content: const Text('This Flutter rebuild keeps the original local-first behavior. Replace this placeholder with the production policy text used by the Kotlin release.'), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))]));
  }
}

class _AboutLinkButton extends StatelessWidget {
  const _AboutLinkButton({required this.link});

  final _AboutLink link;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: link.label,
      child: MotionInkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: () => launchUrl(Uri.parse(link.url), mode: LaunchMode.externalApplication),
        child: SizedBox(
          width: 74,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest.withOpacity(0.72),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: scheme.outlineVariant.withOpacity(0.25)),
                ),
                child: Icon(link.icon, size: 26, color: scheme.onSurface),
              ),
              const SizedBox(height: 6),
              Text(
                link.shortLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                      fontWeight: FontWeight.w800,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LicensePackageSummary {
  const _LicensePackageSummary({required this.name, required this.entries});

  final String name;
  final int entries;
}

class KoinlyLicenseScreen extends StatefulWidget {
  const KoinlyLicenseScreen({super.key});

  @override
  State<KoinlyLicenseScreen> createState() => _KoinlyLicenseScreenState();
}

class _KoinlyLicenseScreenState extends State<KoinlyLicenseScreen> {
  late final Future<List<_LicensePackageSummary>> _licensesFuture = _loadLicenseSummaries();

  Future<List<_LicensePackageSummary>> _loadLicenseSummaries() async {
    final counts = <String, int>{};
    await for (final entry in LicenseRegistry.licenses) {
      for (final package in entry.packages) {
        counts[package] = (counts[package] ?? 0) + 1;
      }
    }
    final summaries = counts.entries
        .map((entry) => _LicensePackageSummary(name: entry.key, entries: entry.value))
        .toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return summaries;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return PageScaffold(
      title: 'Licenses',
      subtitle: 'Open-source notices',
      child: FutureBuilder<List<_LicensePackageSummary>>(
        future: _licensesFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const KoinlyPageLoader();
          }
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Could not load open-source licenses.',
                  style: Theme.of(context).textTheme.titleMedium,
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          final licenses = snapshot.data ?? const <_LicensePackageSummary>[];
          return LayoutBuilder(
            builder: (context, constraints) {
              final screenWidth = MediaQuery.sizeOf(context).width;
              final desktop = screenWidth >= AppBreakpoints.expanded;
              final small = screenWidth < AppBreakpoints.compact;
              final maxWidth = desktop ? 980.0 : 720.0;
              final width = math.min(constraints.maxWidth, maxWidth).toDouble();
              final padding = EdgeInsets.fromLTRB(
                desktop ? 32 : small ? 14 : 18,
                desktop ? 22 : 12,
                desktop ? 32 : small ? 14 : 18,
                desktop ? 42 : 110,
              );

              return Align(
                alignment: Alignment.topCenter,
                child: SizedBox(
                  width: width,
                  child: ListView.builder(
                    padding: padding,
                    physics: optimizedScrollPhysics(context),
                    addAutomaticKeepAlives: false,
                    addSemanticIndexes: false,
                    itemCount: licenses.length + 1,
                    itemBuilder: (context, index) {
                      if (index == 0) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: ExpressiveCard(
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
                            child: Column(
                              children: [
                                Container(
                                  width: 72,
                                  height: 72,
                                  decoration: BoxDecoration(
                                    color: kSleekAccent.withOpacity(.16),
                                    borderRadius: AppShapes.large,
                                    border: Border.all(color: kSleekAccent.withOpacity(.22)),
                                  ),
                                  child: const Icon(Icons.account_balance_wallet_rounded, color: kSleekAccent, size: 38),
                                ),
                                const SizedBox(height: 14),
                                Text(appTitle, style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w900), textAlign: TextAlign.center),
                                const SizedBox(height: 4),
                                Text('Version $appVersion', style: Theme.of(context).textTheme.titleMedium?.copyWith(color: scheme.onSurfaceVariant, fontWeight: FontWeight.w800), textAlign: TextAlign.center),
                                const SizedBox(height: 12),
                                Text(
                                  'Powered by Flutter • ${licenses.length} packages with license notices',
                                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant, fontWeight: FontWeight.w700),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          ),
                        );
                      }

                      final item = licenses[index - 1];
                      final countLabel = item.entries == 1 ? '1 license' : '${item.entries} licenses';
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: ExpressiveCard(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          child: ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                color: kSleekAccent.withOpacity(.14),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: kSleekAccent.withOpacity(.20)),
                              ),
                              child: const Icon(Icons.article_rounded, color: kSleekAccent),
                            ),
                            title: Text(
                              item.name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.w900),
                            ),
                            subtitle: Text(countLabel, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: kSleekMuted, fontWeight: FontWeight.w700)),
                            trailing: Icon(Icons.chevron_right_rounded, color: scheme.onSurfaceVariant),
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => KoinlyLicenseDetailScreen(packageName: item.name, licenseCount: item.entries)),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class KoinlyLicenseDetailScreen extends StatefulWidget {
  const KoinlyLicenseDetailScreen({super.key, required this.packageName, required this.licenseCount});

  final String packageName;
  final int licenseCount;

  @override
  State<KoinlyLicenseDetailScreen> createState() => _KoinlyLicenseDetailScreenState();
}

class _KoinlyLicenseDetailScreenState extends State<KoinlyLicenseDetailScreen> {
  late final Future<List<LicenseEntry>> _entriesFuture = _loadEntries();

  Future<List<LicenseEntry>> _loadEntries() async {
    final entries = <LicenseEntry>[];
    await for (final entry in LicenseRegistry.licenses) {
      if (entry.packages.contains(widget.packageName)) {
        entries.add(entry);
      }
    }
    return entries;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return PageScaffold(
      title: widget.packageName,
      subtitle: widget.licenseCount == 1 ? '1 license notice' : '${widget.licenseCount} license notices',
      child: FutureBuilder<List<LicenseEntry>>(
        future: _entriesFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const KoinlyPageLoader();
          }
          final entries = snapshot.data ?? const <LicenseEntry>[];
          return LayoutBuilder(
            builder: (context, constraints) {
              final screenWidth = MediaQuery.sizeOf(context).width;
              final desktop = screenWidth >= AppBreakpoints.expanded;
              final small = screenWidth < AppBreakpoints.compact;
              final maxWidth = desktop ? 980.0 : 720.0;
              final width = math.min(constraints.maxWidth, maxWidth).toDouble();
              final padding = EdgeInsets.fromLTRB(
                desktop ? 32 : small ? 14 : 18,
                desktop ? 22 : 12,
                desktop ? 32 : small ? 14 : 18,
                desktop ? 42 : 110,
              );

              return Align(
                alignment: Alignment.topCenter,
                child: SizedBox(
                  width: width,
                  child: SelectionArea(
                    child: ListView.builder(
                      padding: padding,
                      physics: optimizedScrollPhysics(context),
                      addAutomaticKeepAlives: false,
                      addSemanticIndexes: false,
                      itemCount: entries.length + 1,
                      itemBuilder: (context, index) {
                        if (index == 0) {
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 16),
                            child: ExpressiveCard(
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(widget.packageName, style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w900)),
                                  const SizedBox(height: 8),
                                  Text(
                                    widget.licenseCount == 1 ? '1 license notice' : '${widget.licenseCount} license notices',
                                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant, fontWeight: FontWeight.w700),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }

                        final entry = entries[index - 1];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 14),
                          child: ExpressiveCard(
                            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: entry.paragraphs
                                  .map(
                                    (paragraph) => Padding(
                                      padding: EdgeInsets.only(left: paragraph.indent == LicenseParagraph.centeredIndent ? 0 : paragraph.indent * 16.0, bottom: 10),
                                      child: SelectableText(
                                        paragraph.text,
                                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                              color: scheme.onSurfaceVariant,
                                              height: 1.42,
                                              fontWeight: paragraph.indent == LicenseParagraph.centeredIndent ? FontWeight.w800 : FontWeight.w500,
                                            ),
                                        textAlign: paragraph.indent == LicenseParagraph.centeredIndent ? TextAlign.center : TextAlign.start,
                                      ),
                                    ),
                                  )
                                  .toList(),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
