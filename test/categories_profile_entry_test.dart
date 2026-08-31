import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koinly/main.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('Categories header exposes Profile and omits the date-range button', (tester) async {
    final controller = AppController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      ChangeNotifierProvider<AppController>.value(
        value: controller,
        child: const MaterialApp(home: CategoriesScreen()),
      ),
    );

    expect(find.byType(ProfileAvatarButton), findsOneWidget);
    expect(find.text('All time'), findsNothing);
    expect(find.text('All Time'), findsNothing);
  });
}
