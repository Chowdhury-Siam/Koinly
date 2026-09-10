import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every app TextField dismisses focus when the user taps outside it', () {
    final files = [
      File('lib/main.dart'),
      File('lib/loans/loan_sheets.dart'),
      File('lib/loans/loan_screens.dart'),
      File('lib/profile/profile_ui.dart'),
    ];

    var fields = 0;
    var dismissHandlers = 0;
    for (final file in files) {
      final source = file.readAsStringSync();
      fields += RegExp(r'\bTextField\(').allMatches(source).length;
      dismissHandlers += RegExp(r'onTapOutside:\s*\(_\)\s*=>\s*FocusManager\.instance\.primaryFocus\?\.unfocus\(\)').allMatches(source).length;
    }

    expect(fields, greaterThan(0));
    expect(dismissHandlers, fields);
  });
}
