import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koinly/main.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('home dashboard renders the redesigned hero and sections', (tester) async {
    final controller = AppController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider<AppController>.value(
        value: controller,
        child: const MaterialApp(home: HomeDashboardScreen()),
      ),
    );

    // Hero label and welcome header.
    expect(find.text('TOTAL BALANCE'), findsOneWidget);
    expect(find.textContaining('Welcome back'), findsOneWidget);
    // Reference-style section headers.
    expect(find.text('YOUR ACCOUNTS'), findsOneWidget);
    expect(find.text('No accounts yet'), findsWidgets);
    expect(find.text('View activity'), findsOneWidget);
    // Theme toggle affordance exists.
    expect(find.byTooltip('Toggle theme'), findsOneWidget);
    // Avatar opens the profile (existing feature).
    expect(find.byTooltip('Open profile'), findsOneWidget);
  });

  testWidgets('main shell shows the floating dock on compact widths', (tester) async {
    final controller = AppController();
    addTearDown(controller.dispose);

    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ChangeNotifierProvider<AppController>.value(
        value: controller,
        child: const MaterialApp(home: MainShell()),
      ),
    );

    // Dock items with reference naming.
    expect(find.text('Home'), findsWidgets);
    expect(find.text('Insights'), findsWidgets);
    expect(find.text('Loans'), findsWidgets);
    expect(find.text('Activity'), findsWidgets);
    expect(find.text('Categories'), findsWidgets);
    // Quick-add FAB is present on mobile.
    expect(find.byTooltip('Add transaction'), findsOneWidget);
  });

  testWidgets('main shell shows the reference sidebar on wide layouts', (tester) async {
    final controller = AppController();
    addTearDown(controller.dispose);

    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ChangeNotifierProvider<AppController>.value(
        value: controller,
        child: const MaterialApp(home: MainShell()),
      ),
    );

    // Sidebar brand block.
    expect(find.text('Koinly'), findsOneWidget);
    expect(find.text('PRIVATE FINANCE'), findsOneWidget);
    // Local-only mode card (cloud sync disabled by default).
    expect(find.text('LOCAL-ONLY MODE'), findsOneWidget);
    expect(find.text('Device sync'), findsOneWidget);
    // Sidebar settings entry (reference layout). 'Home' also appears as the
    // page title of the active tab.
    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Home'), findsWidgets);
    expect(find.text('Insights'), findsOneWidget);
  });
}
