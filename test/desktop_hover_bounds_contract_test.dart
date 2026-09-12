import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('desktop hover visuals stay inside the complete pointer hit surface', () {
    final foundation = File('lib/ui_foundation.dart').readAsStringSync();
    final mainSource = File('lib/main.dart').readAsStringSync();

    // Hover animation remains, but it may not paint beyond the MouseRegion.
    expect(foundation, contains("_hovered ? 1.0 : .994"));
    expect(foundation, contains("_hovered ? 1.0 : .996"));
    expect(foundation, isNot(contains('_hovered ? 1.008 : 1.0')));
    expect(foundation, isNot(contains('_hovered ? 1.006 : 1.0')));

    // Material controls keep hover feedback with explicit bounded state fills.
    expect(mainSource, contains('hoverColor: kSleekAccent.withOpacity'));
    expect(mainSource, contains('focusColor: kSleekAccent.withOpacity'));
    expect(mainSource, contains('state.contains(WidgetState.hovered)'));
    expect(mainSource, contains('overlayColor: const WidgetStatePropertyAll(Colors.transparent)'));
  });
}
