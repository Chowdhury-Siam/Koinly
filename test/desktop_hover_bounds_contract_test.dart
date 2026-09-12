import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('desktop hover never paints an overlay outside rounded control bounds', () {
    final mainSource = File('lib/main.dart').readAsStringSync();
    final foundation = File('lib/ui_foundation.dart').readAsStringSync();

    expect(mainSource, contains('hoverColor: Colors.transparent'));
    expect(
      mainSource,
      contains("state.contains(WidgetState.pressed)"),
    );
    expect(
      foundation,
      contains('double get _restScale => 1.0;'),
    );
    expect(
      foundation,
      isNot(contains('kIsDesktopApp && _hovered ? 1.008 : 1.0')),
    );
    expect(
      foundation,
      isNot(contains('kIsDesktopApp && _hovered ? 1.006 : 1.0')),
    );
  });
}
