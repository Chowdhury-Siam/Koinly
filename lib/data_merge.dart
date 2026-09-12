import 'category_deduplication.dart';

class FinanceDatabaseMergeResult {
  const FinanceDatabaseMergeResult({
    required this.database,
    required this.categoryPlan,
  });

  final Map<String, dynamic> database;
  final CategoryMergePlan categoryPlan;
}

const _entityTables = <String>[
  'accounts',
  'categories',
  'planned_purchases',
  'subscriptions',
  'transactions',
  'budgets',
  'loan_contacts',
  'loans',
  'loan_payments',
];

const _joinTables = <String>[
  'budget_accounts',
  'budget_categories',
];

/// Produces a non-destructive union of two finance database payloads.
///
/// Rows with different IDs are preserved. When both payloads contain the same
/// entity ID, the row with the newest `updated_on` (falling back to
/// `created_on`) wins. Category identity is additionally normalized by
/// type + case-insensitive display name so independently-created categories
/// such as "Food" are represented once and all references are remapped.
FinanceDatabaseMergeResult mergeFinanceDatabasePayloads(
  Map<String, dynamic> current,
  Map<String, dynamic> incoming,
) {
  final merged = <String, dynamic>{};

  for (final table in _entityTables) {
    merged[table] = _mergeEntityRows(
      _rows(current[table]),
      _rows(incoming[table]),
    );
  }

  for (final table in _joinTables) {
    merged[table] = _mergeJoinRows(table, _rows(current[table]), _rows(incoming[table]));
  }

  final normalized = normalizeCategoryDatabasePayload(merged);
  return FinanceDatabaseMergeResult(
    database: normalized.database,
    categoryPlan: normalized.plan,
  );
}

Map<String, dynamic> mergeFinancePreferences(
  Map<String, dynamic> current,
  Map<String, dynamic> incoming,
  CategoryMergePlan categoryPlan,
) {
  final merged = Map<String, dynamic>.from(current);

  // An explicit restore should adopt incoming scalar preferences, while list
  // preferences are unions so useful local selections/history are not lost.
  for (final entry in incoming.entries) {
    final value = entry.value;
    if (value is List) {
      merged[entry.key] = _mergeListValues(merged[entry.key], value);
    } else if (value is Map && merged[entry.key] is Map) {
      merged[entry.key] = <String, dynamic>{
        ...(merged[entry.key] as Map).cast<String, dynamic>(),
        ...value.cast<String, dynamic>(),
      };
    } else {
      merged[entry.key] = value;
    }
  }

  // These IDs can reference a category that was collapsed while combining the
  // two database payloads.
  return remapCategoryPreferences(merged, categoryPlan);
}

List<Map<String, Object?>> _mergeEntityRows(
  List<Map<String, Object?>> current,
  List<Map<String, Object?>> incoming,
) {
  final byId = <String, Map<String, Object?>>{};
  final withoutId = <Map<String, Object?>>[];

  void absorb(Map<String, Object?> row, {required bool incomingRow}) {
    final id = row['id']?.toString() ?? '';
    if (id.isEmpty) {
      withoutId.add(Map<String, Object?>.from(row));
      return;
    }
    final existing = byId[id];
    if (existing == null) {
      byId[id] = Map<String, Object?>.from(row);
      return;
    }
    final comparison = _rowTimestamp(row).compareTo(_rowTimestamp(existing));
    if (comparison > 0 || (comparison == 0 && incomingRow)) {
      byId[id] = Map<String, Object?>.from(row);
    }
  }

  for (final row in current) {
    absorb(row, incomingRow: false);
  }
  for (final row in incoming) {
    absorb(row, incomingRow: true);
  }

  return [...byId.values, ...withoutId];
}

List<Map<String, Object?>> _mergeJoinRows(
  String table,
  List<Map<String, Object?>> current,
  List<Map<String, Object?>> incoming,
) {
  final byKey = <String, Map<String, Object?>>{};
  for (final row in [...current, ...incoming]) {
    final budgetId = row['budget_id']?.toString() ?? '';
    final secondId = table == 'budget_accounts'
        ? row['account_id']?.toString() ?? ''
        : row['category_id']?.toString() ?? '';
    if (budgetId.isEmpty || secondId.isEmpty) continue;
    byKey['$budgetId\u0000$secondId'] = Map<String, Object?>.from(row);
  }
  return byKey.values.toList();
}

List<dynamic> _mergeListValues(Object? current, List<dynamic> incoming) {
  final result = <dynamic>[];
  final seen = <String>{};
  for (final value in [...(current is List ? current : const []), ...incoming]) {
    final key = _stableValueKey(value);
    if (seen.add(key)) result.add(value);
  }
  return result;
}

String _stableValueKey(Object? value) {
  if (value is Map) {
    final entries = value.entries.map((entry) => '${entry.key}:${_stableValueKey(entry.value)}').toList()..sort();
    return '{${entries.join(',')}}';
  }
  if (value is List) return '[${value.map(_stableValueKey).join(',')}]';
  return '${value.runtimeType}:$value';
}

int _rowTimestamp(Map<String, Object?> row) {
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

List<Map<String, Object?>> _rows(Object? value) =>
    (value as List? ?? const []).whereType<Map>().map((row) => Map<String, Object?>.from(row)).toList();
