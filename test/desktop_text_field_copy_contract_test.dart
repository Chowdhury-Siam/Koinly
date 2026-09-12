import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every app TextField exposes the adaptive selection context menu', () {
    final files = [
      File('lib/main.dart'),
      File('lib/loans/loan_sheets.dart'),
      File('lib/loans/loan_screens.dart'),
      File('lib/profile/profile_ui.dart'),
    ];

    var fields = 0;
    var contextMenus = 0;
    var interactiveSelections = 0;
    for (final file in files) {
      final source = file.readAsStringSync();
      fields += RegExp(r'\bTextField\(').allMatches(source).length;
      contextMenus += RegExp(r'contextMenuBuilder:\s*koinlyTextFieldContextMenu').allMatches(source).length;
      interactiveSelections += RegExp(r'enableInteractiveSelection:\s*true').allMatches(source).length;
    }

    expect(fields, greaterThan(0));
    expect(contextMenus, fields);
    expect(interactiveSelections, fields);
  });

  test('shared context menu uses Flutter adaptive copy/paste controls', () {
    final source = File('lib/ui_foundation.dart').readAsStringSync();
    expect(source, contains('Widget koinlyTextFieldContextMenu('));
    expect(source, contains('AdaptiveTextSelectionToolbar.buttonItems('));
    expect(source, contains('editableTextState.contextMenuButtonItems'));
  });

  test('signed-in and busy sync fields stay selectable by using readOnly', () {
    final source = File('lib/main.dart').readAsStringSync();
    expect(source, contains('readOnly: busy || signedIn,'));
    expect(source, isNot(contains('enabled: !busy && !signedIn,')));
  });
}
