import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koinly/main.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('selecting self-hosted removes the registration key field', (tester) async {
    final controller = AppController();

    await tester.pumpWidget(
      ChangeNotifierProvider<AppController>.value(
        value: controller,
        child: const MaterialApp(
          home: MultiDeviceSyncScreen(initialRegisterMode: true),
        ),
      ),
    );

    expect(find.text('Registration Key'), findsOneWidget);

    await tester.tap(find.text('Self-hosted'));
    await tester.pump();

    expect(find.text('Registration Key'), findsNothing);
    expect(find.text('A valid single-use invitation key is required.'), findsNothing);
  });
}
