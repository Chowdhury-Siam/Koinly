import 'package:flutter_test/flutter_test.dart';
import 'package:koinly/category_deduplication.dart';

Map<String, dynamic> duplicateCategoryPayload() => {
      'categories': [
        {
          'id': 'expense-clothing-copy',
          'type': 'expense',
          'name': '  clothing  ',
          'created_on': 200,
        },
        {
          'id': 'expense-clothing-original',
          'type': 'expense',
          'name': 'Clothing',
          'created_on': 100,
        },
        {
          'id': 'income-clothing',
          'type': 'income',
          'name': 'Clothing',
          'created_on': 50,
        },
      ],
      'transactions': [
        {'id': 'transaction-copy', 'category_id': 'expense-clothing-copy'},
        {'id': 'transaction-original', 'category_id': 'expense-clothing-original'},
      ],
      'budget_categories': [
        {'budget_id': 'budget-1', 'category_id': 'expense-clothing-copy'},
        {'budget_id': 'budget-1', 'category_id': 'expense-clothing-original'},
      ],
    };

void main() {
  test('duplicate categories merge by normalized name and type', () {
    final result = normalizeCategoryDatabasePayload(duplicateCategoryPayload());

    expect(result.plan.duplicateToCanonicalId, {
      'expense-clothing-copy': 'expense-clothing-original',
    });
    final categories = (result.database['categories'] as List).cast<Map>();
    expect(categories.map((row) => row['id']), containsAll(['expense-clothing-original', 'income-clothing']));
    expect(categories, hasLength(2));
  });

  test('transaction and budget references follow the canonical category', () {
    final result = normalizeCategoryDatabasePayload(duplicateCategoryPayload());
    final transactions = (result.database['transactions'] as List).cast<Map>();
    final budgetCategories = (result.database['budget_categories'] as List).cast<Map>();

    expect(transactions.map((row) => row['category_id']).toSet(), {'expense-clothing-original'});
    expect(budgetCategories, [
      {'budget_id': 'budget-1', 'category_id': 'expense-clothing-original'},
    ]);
  });

  test('category preferences and filters are remapped without duplicates', () {
    final result = normalizeCategoryDatabasePayload(duplicateCategoryPayload());
    final preferences = remapCategoryPreferences({
      'defaultExpenseCategoryId': 'expense-clothing-copy',
      'defaultIncomeCategoryId': 'income-clothing',
      'filterCategoryIds': [
        'expense-clothing-copy',
        'expense-clothing-original',
        'income-clothing',
      ],
    }, result.plan);

    expect(preferences['defaultExpenseCategoryId'], 'expense-clothing-original');
    expect(preferences['defaultIncomeCategoryId'], 'income-clothing');
    expect(preferences['filterCategoryIds'], ['expense-clothing-original', 'income-clothing']);
  });

  test('normalization is deterministic and idempotent', () {
    final payload = duplicateCategoryPayload();
    payload['categories'] = (payload['categories'] as List).reversed.toList();
    final first = normalizeCategoryDatabasePayload(payload);
    final second = normalizeCategoryDatabasePayload(first.database);

    expect(first.plan.duplicateToCanonicalId['expense-clothing-copy'], 'expense-clothing-original');
    expect(second.plan.hasChanges, isFalse);
  });
}
