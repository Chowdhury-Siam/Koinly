import 'package:flutter_test/flutter_test.dart';
import 'package:koinly/data_merge.dart';

void main() {
  test('merge keeps local-only and cloud-only rows', () {
    final result = mergeFinanceDatabasePayloads(
      {
        'accounts': [
          {'id': 'local-account', 'name': 'Cash', 'updated_on': 100},
        ],
      },
      {
        'accounts': [
          {'id': 'cloud-account', 'name': 'Bank', 'updated_on': 200},
        ],
      },
    );

    final accounts = (result.database['accounts'] as List).cast<Map>();
    expect(accounts.map((row) => row['id']).toSet(), {'local-account', 'cloud-account'});
  });

  test('matching entity ID keeps the newer row instead of duplicating it', () {
    final result = mergeFinanceDatabasePayloads(
      {
        'accounts': [
          {'id': 'cash', 'name': 'Cash old', 'amount': 100.0, 'updated_on': 100},
        ],
      },
      {
        'accounts': [
          {'id': 'cash', 'name': 'Cash', 'amount': 250.0, 'updated_on': 200},
        ],
      },
    );

    final accounts = (result.database['accounts'] as List).cast<Map>();
    expect(accounts, hasLength(1));
    expect(accounts.single['name'], 'Cash');
    expect(accounts.single['amount'], 250.0);
  });

  test('same logical Food category is collapsed and every reference is remapped', () {
    final result = mergeFinanceDatabasePayloads(
      {
        'categories': [
          {'id': 'food-local', 'type': 'expense', 'name': 'Food', 'created_on': 100, 'updated_on': 100},
        ],
        'transactions': [
          {'id': 'local-tx', 'category_id': 'food-local', 'updated_on': 100},
        ],
        'budget_categories': [
          {'budget_id': 'budget-local', 'category_id': 'food-local'},
        ],
      },
      {
        'categories': [
          {'id': 'food-cloud', 'type': 'expense', 'name': '  food  ', 'created_on': 200, 'updated_on': 200},
        ],
        'transactions': [
          {'id': 'cloud-tx', 'category_id': 'food-cloud', 'updated_on': 200},
        ],
        'budget_categories': [
          {'budget_id': 'budget-cloud', 'category_id': 'food-cloud'},
        ],
      },
    );

    final categories = (result.database['categories'] as List).cast<Map>();
    final transactions = (result.database['transactions'] as List).cast<Map>();
    final budgetCategories = (result.database['budget_categories'] as List).cast<Map>();

    expect(categories, hasLength(1));
    expect(categories.single['id'], 'food-local');
    expect(categories.single['name'], 'Food');
    expect(transactions.map((row) => row['category_id']).toSet(), {'food-local'});
    expect(budgetCategories.map((row) => row['category_id']).toSet(), {'food-local'});
    expect(result.categoryPlan.duplicateToCanonicalId['food-cloud'], 'food-local');
  });

  test('preferences are unioned and category IDs follow the canonical category', () {
    final databaseMerge = mergeFinanceDatabasePayloads(
      {
        'categories': [
          {'id': 'food-local', 'type': 'expense', 'name': 'Food', 'created_on': 100},
        ],
      },
      {
        'categories': [
          {'id': 'food-cloud', 'type': 'expense', 'name': 'food', 'created_on': 200},
        ],
      },
    );

    final preferences = mergeFinancePreferences(
      {
        'defaultExpenseCategoryId': 'food-local',
        'filterCategoryIds': ['food-local', 'other-local'],
        'currencyCode': 'USD',
      },
      {
        'defaultExpenseCategoryId': 'food-cloud',
        'filterCategoryIds': ['food-cloud', 'other-cloud'],
        'currencyCode': 'BDT',
      },
      databaseMerge.categoryPlan,
    );

    expect(preferences['defaultExpenseCategoryId'], 'food-local');
    expect(preferences['filterCategoryIds'], ['food-local', 'other-local', 'other-cloud']);
    // Explicit restore/merge adopts incoming scalar preferences.
    expect(preferences['currencyCode'], 'BDT');
  });
}
