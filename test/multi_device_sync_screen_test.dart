import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koinly/main.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('Account & sync exposes only the self-hosted Worker', (tester) async {
    final controller = AppController();

    await tester.pumpWidget(
      ChangeNotifierProvider<AppController>.value(
        value: controller,
        child: const MaterialApp(
          home: MultiDeviceSyncScreen(initialRegisterMode: true),
        ),
      ),
    );

    expect(find.text('Self-hosted Sync Worker'), findsOneWidget);
    expect(find.text('Cloudflare Worker URL'), findsOneWidget);
    expect(find.text('Validate and use Worker'), findsOneWidget);
    expect(find.text('Default'), findsNothing);
    expect(find.text('Registration Key'), findsNothing);
  });
}
