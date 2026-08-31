import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koinly/main.dart';
import 'package:koinly/models.dart';
import 'package:provider/provider.dart';

MoneyTransaction titledTransaction({String title = 'Lunch with friends', DateTime? endOn}) {
  final now = DateTime.utc(2026, 8, 28, 12, 30);
  return MoneyTransaction(
    id: 'transaction-1',
    type: MoneyTransactionType.expense,
    amount: 24.50,
    title: title,
    notes: 'Cafe',
    categoryId: 'food',
    fromAccountId: 'cash',
    createdOn: now,
    endOn: endOn,
    updatedOn: now,
  );
}

void main() {
  test('transaction title survives map and copy round trips', () {
    final original = titledTransaction();
    final restored = MoneyTransaction.fromMap(original.toMap());

    expect(restored.title, 'Lunch with friends');
    expect(restored.copyWith(title: 'Dinner').title, 'Dinner');
  });

  test('older transaction rows without a title remain readable', () {
    final map = titledTransaction().toMap()..remove('title');
    expect(MoneyTransaction.fromMap(map).title, isEmpty);
  });

  test('transaction date range survives map and copy round trips', () {
    final end = DateTime.utc(2026, 9, 2, 12, 30);
    final original = titledTransaction(endOn: end);
    final restored = MoneyTransaction.fromMap(original.toMap());

    expect(restored.endOn, end);
    expect(restored.spansMultipleDays, isTrue);
    expect(restored.copyWith(endOn: DateTime.utc(2026, 9, 5, 12, 30)).endOn, DateTime.utc(2026, 9, 5, 12, 30));
  });

  test('older transaction rows without an end date remain single-date records', () {
    final map = titledTransaction().toMap()..remove('end_on');
    final restored = MoneyTransaction.fromMap(map);

    expect(restored.endOn, isNull);
    expect(restored.effectiveEndOn, restored.createdOn);
    expect(restored.spansMultipleDays, isFalse);
  });

  test('transaction date labels include both ends of a multi-day range', () {
    final transaction = titledTransaction(endOn: DateTime.utc(2026, 9, 2, 12, 30));
    expect(transactionDateTimeLabel(transaction), contains('Aug 28 → Sep 2, 2026'));
  });

  test('a ranged transaction amount is counted only once', () {
    final controller = AppController();
    final transaction = titledTransaction(endOn: DateTime.utc(2026, 9, 2, 12, 30));
    final summary = controller.summaryFor([transaction]);

    expect(summary.expense, transaction.amount);
    expect(summary.income, 0);
  });

  testWidgets('transaction history uses the saved title as its primary label', (tester) async {
    final controller = AppController();
    await tester.pumpWidget(
      ChangeNotifierProvider<AppController>.value(
        value: controller,
        child: MaterialApp(
          home: Scaffold(body: TransactionTile(tx: titledTransaction())),
        ),
      ),
    );

    expect(find.text('Lunch with friends'), findsOneWidget);
    expect(find.textContaining('Cafe'), findsOneWidget);
  });

  testWidgets('transaction history displays a saved date range', (tester) async {
    final controller = AppController();
    await tester.pumpWidget(
      ChangeNotifierProvider<AppController>.value(
        value: controller,
        child: MaterialApp(
          home: Scaffold(
            body: TransactionTile(
              tx: titledTransaction(endOn: DateTime.utc(2026, 9, 2, 12, 30)),
            ),
          ),
        ),
      ),
    );

    expect(find.textContaining('Aug 28 → Sep 2, 2026'), findsOneWidget);
  });

  testWidgets('title input is available for expense and income but not transfer', (tester) async {
    final controller = AppController();
    await tester.pumpWidget(
      ChangeNotifierProvider<AppController>.value(
        value: controller,
        child: const MaterialApp(
          home: Scaffold(body: TransactionEditor()),
        ),
      ),
    );

    expect(find.widgetWithText(TextField, 'Title'), findsOneWidget);
    await tester.tap(find.text('Income'));
    await tester.pump();
    expect(find.widgetWithText(TextField, 'Title'), findsOneWidget);

    await tester.tap(find.text('Transfer'));
    await tester.pump();
    expect(find.widgetWithText(TextField, 'Title'), findsNothing);
  });
}
