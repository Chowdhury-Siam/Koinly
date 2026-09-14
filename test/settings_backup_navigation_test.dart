import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koinly/main.dart';
import 'package:provider/provider.dart';

Future<void> pumpSettingsScreen(WidgetTester tester, Widget screen) async {
  final controller = AppController();
  addTearDown(controller.dispose);
  await tester.pumpWidget(
    ChangeNotifierProvider<AppController>.value(
      value: controller,
      child: MaterialApp(home: screen),
    ),
  );
}

void main() {
  testWidgets('main Settings is grouped and exposes Credential and Archive', (tester) async {
    await pumpSettingsScreen(tester, const SettingsScreen());

    expect(find.text('General'), findsOneWidget);
    expect(find.text('Data & cloud'), findsOneWidget);
    expect(find.text('App'), findsOneWidget);
    expect(find.text('Credential'), findsOneWidget);
    expect(find.text('Archive'), findsOneWidget);
    expect(find.text('Load backup'), findsNothing);
    expect(find.text('Local Backup'), findsNothing);
  });

  testWidgets('Profile keeps information and editable media framing only', (tester) async {
    await pumpSettingsScreen(tester, const ProfileScreen());

    expect(find.text('Profile information'), findsOneWidget);
    expect(find.text('Profile media'), findsOneWidget);
    expect(find.text('Bio'), findsNothing);
    expect(find.text('Savings Suggestion'), findsNothing);
  });

  testWidgets('Archive owns backup and scheduled delivery controls', (tester) async {
    await pumpSettingsScreen(tester, const ArchiveSettingsScreen());

    expect(find.text('Local'), findsNWidgets(2));
    expect(find.text('Local backup File'), findsOneWidget);
    expect(find.text('Cloud'), findsNWidgets(2));
    expect(find.text('Backup'), findsOneWidget);
    expect(find.text('Local Backup'), findsNothing);
    expect(find.text('Load backup'), findsOneWidget);
    expect(find.text('Telegram Backup'), findsNothing);
    expect(find.text('Cloud Backup'), findsOneWidget);
  });

  testWidgets('Advanced settings no longer contains backup controls', (tester) async {
    await pumpSettingsScreen(tester, const AdvancedSettingsScreen());

    expect(find.text('Backup'), findsNothing);
    expect(find.text('Local Backup'), findsNothing);
    expect(find.text('Load backup'), findsNothing);
    expect(find.text('Data health'), findsOneWidget);
  });
}
