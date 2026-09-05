import 'package:flutter/material.dart' hide Category, Summary;
import 'package:flutter_test/flutter_test.dart';
import 'package:koinly/design_system.dart';
import 'package:koinly/main.dart';
import 'package:koinly/models.dart';
import 'package:provider/provider.dart';

AppController fixture() {
  final state = AppController();
  final now = DateTime.now();
  state.accounts = [
    for (final type in AccountType.values)
      Account(id: type.name, name: '${type.name} account', type: type,
        iconName: 'wallet', iconColor: '#FF2D68', amount: type == AccountType.credit ? -1240.78 : 4820.45,
        creditLimit: type == AccountType.credit ? 8000 : 0, sequence: 0, createdOn: now, updatedOn: now),
  ];
  return state;
}

Future<void> mount(WidgetTester tester, AppController state, Widget page,
    Brightness brightness, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(ChangeNotifierProvider<AppController>.value(value: state,
    child: MaterialApp(theme: KoinlyDesign.theme(brightness),
      builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(
        disableAnimations: true, textScaler: const TextScaler.linear(1.14)), child: child!),
      home: page)));
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  // These regression checks require Flutter; they are included for native CI.
  for (final brightness in Brightness.values) {
    for (final width in [360.0, 390.0, 1024.0, 1440.0]) {
      for (final entry in <String, Widget>{
        'Home': const HomeDashboardScreen(),
        'Activity': const TransactionListScreen(),
        'Insights': const AnalysisScreen(),
        'Loans': const LoansScreen(),
        'Categories': const CategoriesScreen(),
        'Settings': const SettingsScreen(),
      }.entries) {
        testWidgets('${entry.key} at $width / ${brightness.name} has no layout exceptions', (tester) async {
          final state = fixture();
          addTearDown(state.dispose);
          await mount(tester, state, entry.value, brightness, Size(width, 900));
          expect(tester.takeException(), isNull);
        });
      }
    }
  }

  testWidgets('transaction editor retains transfer fields and notes', (tester) async {
    final state = fixture();
    addTearDown(state.dispose);
    await mount(tester, state, const Scaffold(body: SingleChildScrollView(child: TransactionEditor())),
      Brightness.light, const Size(390, 1100));
    await tester.tap(find.text('Transfer'));
    await tester.pump();
    expect(find.text('From account'), findsOneWidget);
    expect(find.text('To account'), findsOneWidget);
    expect(find.text('Notes'), findsOneWidget);
    expect(find.byType(KoinlyPrimaryAction), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
