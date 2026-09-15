import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:koinly/main.dart';
import 'package:koinly/models.dart' as models;

Future<List<int>> pixelsAt(WidgetTester tester, GlobalKey key, List<Offset> points) async {
  return (await tester.runAsync(() async {
    final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage();
    final bytes = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    final pixels = points.map((point) {
      final local = boundary.globalToLocal(point);
      return bytes.getUint32((local.dy.floor() * image.width + local.dx.floor()) * 4);
    }).toList();
    image.dispose();
    return pixels;
  }))!;
}

void main() {
  final date = DateTime(2026, 9);
  final account = models.Account(id: 'sample', name: 'Bank', type: models.AccountType.regular,
    iconName: 'wallet', iconColor: '#00BD91', amount: 100, creditLimit: 0,
    sequence: 0, createdOn: date, updatedOn: date);
  final category = models.Category(id: 'sample', name: 'Food', type: models.CategoryType.expense,
    iconName: 'food', iconColor: '#00BD91', createdOn: date, updatedOn: date);
  final cards = <String, Widget Function(VoidCallback)> {
    'Home': (tap) => HomeNavigationTile(iconName: 'wallet', iconColor: '#00BD91',
      title: 'Accounts', subtitle: '2 accounts', amount: '100', onTap: tap),
    'Accounts': (tap) => AccountTile(account: account, onTap: tap),
    'Categories': (tap) => CategoryTile(category: category, onTap: tap),
    'Settings': (tap) => SettingsTile(icon: Icons.settings, title: 'Settings',
      subtitle: 'Preferences', color: '#00BD91', onTap: tap),
    'Custom content': (tap) => ExpressiveCard(onTap: tap,
      child: const SizedBox(height: 60, child: Center(child: Text('Open')))),
  };

  for (final brightness in Brightness.values) {
    for (final entry in cards.entries) {
      testWidgets('${entry.key}: full-surface hover, edge click and keyboard (${brightness.name})', (tester) async {
        final controller = AppController();
        final captureKey = GlobalKey();
        var taps = 0;
        await tester.pumpWidget(ChangeNotifierProvider<AppController>.value(
          value: controller,
          child: Builder(builder: (context) {
            final app = const KoinlyApp().build(context) as MaterialApp;
            return MaterialApp(
              theme: brightness == Brightness.dark ? app.darkTheme : app.theme,
              home: RepaintBoundary(key: captureKey, child: Scaffold(
                body: Center(child: SizedBox(width: 500, child: entry.value(() => taps++))),
              )),
            );
          }),
        ));
        await tester.pumpAndSettle();
        final rect = tester.getRect(find.byType(ExpressiveCard));
        final points = [
          rect.centerLeft + const Offset(5, 0),
          rect.topCenter + const Offset(0, 4),
          rect.centerRight - const Offset(5, 0),
          rect.topLeft + const Offset(2, 2), // Outside the rounded corner.
        ];
        final before = await pixelsAt(tester, captureKey, points);
        final mouse = await tester.createGesture(kind: ui.PointerDeviceKind.mouse);
        await mouse.addPointer(location: Offset.zero);
        await mouse.moveTo(points.first);
        await tester.pumpAndSettle();
        final hovered = await pixelsAt(tester, captureKey, points);
        for (var i = 0; i < 3; i++) {
          expect(hovered[i], isNot(before[i]), reason: 'Hover must reach each padded edge.');
        }
        expect(hovered.last, before.last, reason: 'Ink must stay inside the rounded outline.');
        await tester.tapAt(points.first);
        await tester.pumpAndSettle();
        expect(taps, 1, reason: 'Padding is part of the same click target.');
        await mouse.moveTo(Offset.zero);
        await tester.pumpAndSettle();
        final restored = await pixelsAt(tester, captureKey, points);
        expect(restored, before, reason: 'The hover layer must clear when the pointer leaves.');
        // Tab to the card's only action and activate it via Enter.
        final cardInk = find.descendant(of: find.byType(ExpressiveCard), matching: find.byWidgetPredicate(
          (widget) => widget is InkWell && widget.onTap != null,
        ));
        expect(cardInk, findsOneWidget);
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(taps, 2, reason: 'Keyboard activation should invoke the action exactly once.');
        expect(tester.takeException(), isNull);
        await mouse.removePointer();
        await tester.pumpWidget(const SizedBox.shrink());
        controller.dispose();
      });
    }
  }

  testWidgets('Nested action keeps its own callback', (tester) async {
    var cardTaps = 0;
    var buttonTaps = 0;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: ExpressiveCard(
      onTap: () => cardTaps++,
      child: Row(children: [const Expanded(child: Text('Category')),
        IconButton(onPressed: () => buttonTaps++, icon: const Icon(Icons.edit))]),
    ))));
    await tester.tap(find.byType(IconButton));
    expect(buttonTaps, 1);
    expect(cardTaps, 0);
  });
}
