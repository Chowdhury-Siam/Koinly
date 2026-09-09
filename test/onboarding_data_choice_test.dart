import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koinly/main.dart';
import 'package:provider/provider.dart';

Future<AppController> pumpOnboarding(WidgetTester tester) async {
  final controller = AppController();
  addTearDown(controller.dispose);
  await tester.pumpWidget(
    ChangeNotifierProvider<AppController>.value(
      value: controller,
      child: const MaterialApp(home: OnboardingScreen()),
    ),
  );
  await tester.pumpAndSettle();
  return controller;
}

void main() {
  testWidgets('Use offline asks whether to restore or start new', (tester) async {
    await pumpOnboarding(tester);

    await tester.tap(find.text('Use offline'));
    await tester.pumpAndSettle();

    expect(find.text('Set up this device'), findsOneWidget);
    expect(find.text('Restore backup'), findsOneWidget);
    expect(find.text('Start new'), findsOneWidget);
  });

  testWidgets('signed-in unfinished onboarding exposes Continue setup', (tester) async {
    final controller = await pumpOnboarding(tester);
    controller.cloudSyncEnabled = true;
    controller.syncAccountEmail = 'owner@example.com';
    controller.notifyListeners();
    await tester.pumpAndSettle();

    expect(find.text('Continue setup'), findsOneWidget);
    expect(find.text('Login'), findsNothing);
    expect(find.text('Create account'), findsNothing);

    await tester.tap(find.text('Continue setup'));
    await tester.pumpAndSettle();

    expect(find.text('Set up this device'), findsOneWidget);
    expect(find.textContaining('Your sync account is ready.'), findsOneWidget);
  });
}
