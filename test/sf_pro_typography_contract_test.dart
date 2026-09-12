import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the app uses SF Pro Display as the global UI font', () {
    final config = File('lib/app_config.dart').readAsStringSync();
    final main = File('lib/main.dart').readAsStringSync();

    expect(config, contains("const String kAppFontFamily = 'SF Pro Display';"));
    expect(config, contains("'SF Pro Text'"));
    expect(config, contains("'.SF UI Display'"));
    expect(main, contains('fontFamily: kAppFontFamily'));
    expect(main, contains('fontFamilyFallback: kAppFontFamilyFallback'));
    expect(main, contains('DefaultTextStyle.merge('));
    expect(main, isNot(contains("fontFamily: 'Roboto'")));
  });
}
