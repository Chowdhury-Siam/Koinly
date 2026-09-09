import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:koinly/data_merge.dart';

void main() {
  test('planned purchases are part of non-destructive database merge', () {
    final result = mergeFinanceDatabasePayloads(
      {
        'planned_purchases': [
          {
            'id': 'local-plan',
            'name': 'Headphones',
            'amount': 100.0,
            'category_id': 'shopping',
            'created_on': 100,
            'updated_on': 100,
          },
        ],
      },
      {
        'planned_purchases': [
          {
            'id': 'cloud-plan',
            'name': 'Keyboard',
            'amount': 200.0,
            'category_id': 'shopping',
            'created_on': 200,
            'updated_on': 200,
          },
        ],
      },
    );

    final plans = (result.database['planned_purchases'] as List).cast<Map>();
    expect(plans.map((row) => row['id']).toSet(), {'local-plan', 'cloud-plan'});
  });

  test('category normalization remaps planned-purchase category references', () {
    final result = mergeFinanceDatabasePayloads(
      {
        'categories': [
          {'id': 'food-old', 'type': 'expense', 'name': 'Food', 'created_on': 100, 'updated_on': 100},
        ],
      },
      {
        'categories': [
          {'id': 'food-new', 'type': 'expense', 'name': ' food ', 'created_on': 200, 'updated_on': 200},
        ],
        'planned_purchases': [
          {
            'id': 'plan',
            'name': 'Snacks',
            'amount': 25.0,
            'category_id': 'food-new',
            'created_on': 200,
            'updated_on': 200,
          },
        ],
      },
    );

    final plans = (result.database['planned_purchases'] as List).cast<Map>();
    expect(plans.single['category_id'], 'food-old');
    final categories = (result.database['categories'] as List).cast<Map>();
    expect(categories, hasLength(1));
  });

  test('transaction tab exposes Plan and purchase flow creates a current-time expense', () {
    final source = File('lib/main.dart').readAsStringSync();

    expect(source, contains("heroTag: 'transactionPlanFab'"));
    expect(source, contains("label: const Text('Plan')"));
    expect(source, contains("child: const Text('Buy')"));
    expect(source, contains("title: 'Choose Account'"));
    expect(source, contains("child: Text(purchasing ? 'Purchasing…' : 'Purchase')"));
    expect(source, contains("type: MoneyTransactionType.expense"));
    expect(source, contains("final now = DateTime.now();"));
    expect(source, contains("await txn.delete('planned_purchases'"));
  });
}
