import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:koinly/data_merge.dart';

void main() {
  test('transaction quick menu expands to Plan and Subscription over blur', () {
    final app = File('lib/main.dart').readAsStringSync();

    expect(app, contains("heroTag: 'transactionMenuFab'"));
    expect(app, contains('AnimatedIcons.menu_close'));
    expect(app, contains('ui.ImageFilter.blur'));
    expect(app, contains("heroTag: 'transactionPlanFab'"));
    expect(app, contains("heroTag: 'transactionSubscriptionFab'"));
    expect(app, contains("label: const Text('Subscription')"));
    expect(app, contains('MaterialPageRoute(builder: (_) => const SubscriptionScreen())'));
    expect(app, contains('Opening: Plan appears first, then Subscription above it.'));
    expect(app, contains('start: .55'));
    expect(app, contains('end: .95'));
    expect(app, contains('start: .08'));
    expect(app, contains('end: .50'));
    final subscriptionIndex = app.indexOf("heroTag: 'transactionSubscriptionFab'");
    final planIndex = app.indexOf("heroTag: 'transactionPlanFab'");
    expect(subscriptionIndex, greaterThanOrEqualTo(0));
    expect(planIndex, greaterThan(subscriptionIndex));
  });

  test('subscriptions persist, select account/category, and can record manually', () {
    final app = File('lib/main.dart').readAsStringSync();
    final models = File('lib/models.dart').readAsStringSync();

    expect(models, contains('class RecurringSubscription'));
    expect(models, contains('enum SubscriptionFrequency { daily, weekly, monthly, yearly }'));
    expect(app, contains("CREATE TABLE IF NOT EXISTS subscriptions"));
    expect(app, contains("label: 'Spend from account'"));
    expect(app, contains("label: 'Category'"));
    expect(app, contains("labelText: 'Price'"));
    expect(app, contains("labelText: 'Repeat'"));
    expect(app, contains('showSubscriptionFrequencyPopup(context, frequency)'));
    expect(app, contains("Text('Auto pay'"));
    expect(app, contains('auto_pay INTEGER NOT NULL DEFAULT 1'));
    expect(app, contains("label: Text(recording ? 'Adding…' : 'Add now')"));
    expect(app, contains('await SubscriptionBackgroundService.recordNow('));
    expect(app, contains('showSubscriptionManualEntryPopup(context, item)'));
    expect(app, contains("label: 'Spend from account'"));
    expect(app, isNot(contains("await txn.delete('subscriptions'")));
  });

  test('scheduled subscriptions participate in merge and category remapping', () {
    final result = mergeFinanceDatabasePayloads(
      {
        'categories': [
          {'id': 'food-old', 'type': 'expense', 'name': 'Food', 'created_on': 100, 'updated_on': 100},
        ],
        'subscriptions': [
          {
            'id': 'local-sub',
            'name': 'Meal plan',
            'amount': 40.0,
            'category_id': 'food-old',
            'account_id': 'cash',
            'next_due_on': 1000,
            'frequency': 'monthly',
            'created_on': 100,
            'updated_on': 100,
          },
        ],
      },
      {
        'categories': [
          {'id': 'food-new', 'type': 'expense', 'name': ' food ', 'created_on': 200, 'updated_on': 200},
        ],
        'subscriptions': [
          {
            'id': 'cloud-sub',
            'name': 'Cloud meal plan',
            'amount': 50.0,
            'category_id': 'food-new',
            'account_id': 'cash',
            'next_due_on': 2000,
            'frequency': 'monthly',
            'created_on': 200,
            'updated_on': 200,
          },
        ],
      },
    );

    final subscriptions = (result.database['subscriptions'] as List).cast<Map>();
    expect(subscriptions.map((row) => row['id']).toSet(), {'local-sub', 'cloud-sub'});
    expect(subscriptions.map((row) => row['category_id']).toSet(), {'food-old'});
  });

  test('background scheduler is idempotent and survives closed app', () {
    final background = File('lib/update_background_service.dart').readAsStringSync();
    final service = File('lib/subscription_background_service.dart').readAsStringSync();

    expect(background, contains("_backgroundSubscriptionTaskName = 'koinlySubscriptionCheck'"));
    expect(background, contains("tag: 'koinly-subscriptions'"));
    expect(service, contains("'subscription:\$subscriptionId:\${occurrence.millisecondsSinceEpoch}'"));
    expect(service, contains("linked_entity_type': 'subscription'"));
    expect(service, contains('while (!due.isAfter(now)'));
    expect(service, contains('if (!subscription.autoPay'));
    expect(service, contains('String? accountId'));
    expect(service, contains('DateTime? occurredOn'));
    expect(service, contains("UPDATE accounts SET amount = amount - ?"));
  });
}
