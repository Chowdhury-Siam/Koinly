String normalizeCategoryDisplayName(String value) => value.trim().replaceAll(RegExp(r'\s+'), ' ');

String categoryIdentityKey(String type, String name) {
  final normalizedName = normalizeCategoryDisplayName(name).toLowerCase();
  if (normalizedName.isEmpty) return '';
  return '${type.trim().toLowerCase()}\u0000$normalizedName';
}

class CategoryMergePlan {
  const CategoryMergePlan({
    required this.duplicateToCanonicalId,
    required this.normalizedNamesByCanonicalId,
  });

  static const empty = CategoryMergePlan(
    duplicateToCanonicalId: <String, String>{},
    normalizedNamesByCanonicalId: <String, String>{},
  );

  final Map<String, String> duplicateToCanonicalId;
  final Map<String, String> normalizedNamesByCanonicalId;

  bool get hasChanges => duplicateToCanonicalId.isNotEmpty || normalizedNamesByCanonicalId.isNotEmpty;
  Set<String> get canonicalCategoryIds => {
        ...duplicateToCanonicalId.values,
        ...normalizedNamesByCanonicalId.keys,
      };

  String remapCategoryId(String id) => duplicateToCanonicalId[id] ?? id;
}

class NormalizedCategoryDatabasePayload {
  const NormalizedCategoryDatabasePayload({required this.database, required this.plan});

  final Map<String, dynamic> database;
  final CategoryMergePlan plan;
}

CategoryMergePlan buildCategoryMergePlan(Iterable<Map<String, Object?>> categoryRows) {
  final groups = <String, List<_CategoryCandidate>>{};
  for (final row in categoryRows) {
    final id = row['id']?.toString() ?? '';
    final type = row['type']?.toString() ?? '';
    final originalName = row['name']?.toString() ?? '';
    final normalizedName = normalizeCategoryDisplayName(originalName);
    final identity = categoryIdentityKey(type, normalizedName);
    if (id.isEmpty || identity.isEmpty) continue;
    groups.putIfAbsent(identity, () => <_CategoryCandidate>[]).add(
          _CategoryCandidate(
            id: id,
            originalName: originalName,
            normalizedName: normalizedName,
            createdOn: _categoryCreatedOnSortValue(row['created_on']),
          ),
        );
  }

  final duplicateToCanonicalId = <String, String>{};
  final normalizedNamesByCanonicalId = <String, String>{};
  for (final candidates in groups.values) {
    candidates.sort((first, second) {
      final byCreatedOn = first.createdOn.compareTo(second.createdOn);
      return byCreatedOn != 0 ? byCreatedOn : first.id.compareTo(second.id);
    });
    final canonical = candidates.first;
    if (canonical.originalName != canonical.normalizedName) {
      normalizedNamesByCanonicalId[canonical.id] = canonical.normalizedName;
    }
    for (final duplicate in candidates.skip(1)) {
      if (duplicate.id != canonical.id) duplicateToCanonicalId[duplicate.id] = canonical.id;
    }
  }

  if (duplicateToCanonicalId.isEmpty && normalizedNamesByCanonicalId.isEmpty) {
    return CategoryMergePlan.empty;
  }
  return CategoryMergePlan(
    duplicateToCanonicalId: Map.unmodifiable(duplicateToCanonicalId),
    normalizedNamesByCanonicalId: Map.unmodifiable(normalizedNamesByCanonicalId),
  );
}

NormalizedCategoryDatabasePayload normalizeCategoryDatabasePayload(Map<String, dynamic> source) {
  final database = Map<String, dynamic>.from(source);
  final categories = _payloadRows(source['categories']);
  final plan = buildCategoryMergePlan(categories);
  if (!plan.hasChanges) {
    return NormalizedCategoryDatabasePayload(database: database, plan: plan);
  }

  database['categories'] = categories
      .where((row) => !plan.duplicateToCanonicalId.containsKey(row['id']?.toString() ?? ''))
      .map((row) {
        final normalized = Map<String, Object?>.from(row);
        final id = normalized['id']?.toString() ?? '';
        final normalizedName = plan.normalizedNamesByCanonicalId[id];
        if (normalizedName != null) normalized['name'] = normalizedName;
        return normalized;
      })
      .toList();

  database['transactions'] = _payloadRows(source['transactions']).map((row) {
    final normalized = Map<String, Object?>.from(row);
    final categoryId = normalized['category_id']?.toString() ?? '';
    if (categoryId.isNotEmpty) normalized['category_id'] = plan.remapCategoryId(categoryId);
    return normalized;
  }).toList();

  final budgetCategoryKeys = <String>{};
  final budgetCategories = <Map<String, Object?>>[];
  for (final row in _payloadRows(source['budget_categories'])) {
    final normalized = Map<String, Object?>.from(row);
    final budgetId = normalized['budget_id']?.toString() ?? '';
    final categoryId = normalized['category_id']?.toString() ?? '';
    final remappedCategoryId = plan.remapCategoryId(categoryId);
    normalized['category_id'] = remappedCategoryId;
    final key = '$budgetId\u0000$remappedCategoryId';
    if (budgetCategoryKeys.add(key)) budgetCategories.add(normalized);
  }
  database['budget_categories'] = budgetCategories;

  return NormalizedCategoryDatabasePayload(database: database, plan: plan);
}

Map<String, dynamic> remapCategoryPreferences(Map<String, dynamic> source, CategoryMergePlan plan) {
  if (!plan.hasChanges) return Map<String, dynamic>.from(source);
  final preferences = Map<String, dynamic>.from(source);
  for (final key in const ['defaultExpenseCategoryId', 'defaultIncomeCategoryId']) {
    final id = preferences[key]?.toString() ?? '';
    if (id.isNotEmpty) preferences[key] = plan.remapCategoryId(id);
  }
  final filters = preferences['filterCategoryIds'];
  if (filters is List) {
    final seen = <String>{};
    preferences['filterCategoryIds'] = filters
        .map((value) => plan.remapCategoryId(value.toString()))
        .where((id) => id.isNotEmpty && seen.add(id))
        .toList();
  }
  return preferences;
}

List<Map<String, Object?>> _payloadRows(Object? value) =>
    (value as List? ?? const []).whereType<Map>().map((row) => Map<String, Object?>.from(row)).toList();

int _categoryCreatedOnSortValue(Object? value) {
  if (value is num) return value.toInt();
  if (value is String) {
    final integer = int.tryParse(value);
    if (integer != null) return integer;
    final date = DateTime.tryParse(value);
    if (date != null) return date.millisecondsSinceEpoch;
  }
  return 9007199254740991;
}

class _CategoryCandidate {
  const _CategoryCandidate({
    required this.id,
    required this.originalName,
    required this.normalizedName,
    required this.createdOn,
  });

  final String id;
  final String originalName;
  final String normalizedName;
  final int createdOn;
}
