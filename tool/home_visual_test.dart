// Render the production Home widgets with isolated, deterministic sample data.
// Run: flutter test --no-pub tool/home_visual_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:koinly/main.dart';
import 'package:koinly/models.dart' as models;

class _PreviewController extends AppController {
  _PreviewController() {
    amountsHidden = true;
    updateLastCheckedAt = DateTime.now();
    final date = DateTime(2026, 9, 1);
    accounts = List.generate(4, (index) => models.Account(
      id: '$index', name: 'Sample account $index',
      type: index == 3 ? models.AccountType.savings : models.AccountType.regular,
      iconName: 'wallet', iconColor: '#00BD91', amount: 1000,
      creditLimit: 0, sequence: index, createdOn: date, updatedOn: date,
    ));
    categories = [
      models.Category(id: 'outside', name: 'outside', type: models.CategoryType.expense,
        iconName: 'car', iconColor: '#35C76B', createdOn: date, updatedOn: date),
      models.Category(id: 'utilities', name: 'Utilities', type: models.CategoryType.expense,
        iconName: 'bolt', iconColor: '#BED58C', createdOn: date, updatedOn: date),
    ];
  }

  @override
  List<models.Account> get operatingAccounts => accounts.take(3).toList();
  @override
  List<models.Account> get savingAccounts => accounts.skip(3).toList();
  @override
  models.Category? categoryOf(String? id) => categories.where((item) => item.id == id).firstOrNull;
  @override
  Map<String, double> categoryTotals(models.CategoryType type,
      {bool ignoreDate = false, List<models.MoneyTransaction>? source}) =>
      {'outside': 520, 'utilities': 480};
  @override
  models.DateRange activeRange() => models.DateRange(DateTime(2026, 9), DateTime(2026, 10), 'September 2026');
  @override
  Future<int> processDueSubscriptions() async => 0;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    // Widget tests otherwise use Ahem, which cannot represent app typography.
    final fontPath = Platform.environment['KOINLY_PREVIEW_FONT'] ?? r'C:\Windows\Fonts\segoeui.ttf';
    final fontBytes = ByteData.sublistView(await File(fontPath).readAsBytes());
    for (final family in ['.SF Pro Display', 'Roboto', 'Ahem', 'Segoe UI']) {
      await (FontLoader(family)..addFont(Future.value(fontBytes))).load();
    }
    await (FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });

  for (final size in [const Size(1737, 905), const Size(390, 844)]) {
    testWidgets('Home renders without overflow at ${size.width.toInt()}px', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = _PreviewController();
      final captureKey = GlobalKey();
      await tester.pumpWidget(
        ChangeNotifierProvider<AppController>.value(
          value: controller,
          child: Builder(builder: (context) {
            final app = const KoinlyApp().build(context) as MaterialApp;
            return MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: app.darkTheme,
              scrollBehavior: app.scrollBehavior,
              home: const MainShell(),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(disableAnimations: true),
                child: RepaintBoundary(key: captureKey, child: child!),
              ),
            );
          }),
        ),
      );
      await tester.runAsync(() async {
        await precacheImage(const AssetImage('assets/icons/koinly_mark.png'),
            tester.element(find.byType(MainShell)));
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(tester.takeException(), isNull);
      expect(find.text('Net Balance'), findsOneWidget);
      expect(find.text('Savings Accounts'), findsOneWidget);
      if (size.width >= 900) {
        final budgetButton = tester.getRect(find.widgetWithText(FilledButton, 'Create budget'));
        expect(budgetButton.bottom, lessThan(size.height - 24),
            reason: 'The desktop budget action should fit fully in the reference viewport.');
        expect(tester.getTopLeft(find.text('Category spending')).dx,
            greaterThan(tester.getTopRight(find.byType(BalanceHeroCard)).dx),
            reason: 'Desktop category spending belongs in the right column.');
      }
      final boundary = captureKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final image = await boundary.toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        final output = Directory('build/ui-comparison')..createSync(recursive: true);
        await File('${output.path}/home-${size.width.toInt()}.png').writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
    });
  }
}
