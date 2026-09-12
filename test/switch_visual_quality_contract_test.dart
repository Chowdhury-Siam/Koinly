import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('shared switch theme removes the heavy track outline globally', () {
    final source = File('lib/main.dart').readAsStringSync();

    expect(source, contains('switchTheme: SwitchThemeData('));
    expect(
      source,
      contains('trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent)'),
    );
    expect(source, contains('scheme.onSurfaceVariant.withOpacity(.72)'));
  });
}
