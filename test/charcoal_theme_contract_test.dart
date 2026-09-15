import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('shared visual system keeps charcoal surfaces and teal accents', () {
    final config = File('lib/app_config.dart').readAsStringSync();
    final mainSource = File('lib/main.dart').readAsStringSync();

    expect(config, contains('kSleekAccent = Color(0xFF00BD91)'));
    expect(config, contains('kSleekBackground = Color(0xFF0F1216)'));
    expect(config, contains('kSleekSurface = Color(0xFF13181D)'));
    expect(config, contains("kSleekAccentHex = '#00BD91'"));
    expect(mainSource, contains('surfaceContainerLow: kSleekSurfaceLow'));
    expect(mainSource, contains('surfaceContainer: kSleekSurfaceContainer'));
    expect(mainSource, contains('outlineVariant: kSleekOutlineVariant'));
    expect(mainSource, contains('return ColoredBox(\n      color: kSleekBackground,'));
    expect(mainSource, isNot(contains('colors: [Color(0xFF071711), kSleekBackground, Color(0xFF091914)]')));
    expect(mainSource, isNot(contains('0xFF00D7E8')));
    expect(mainSource, isNot(contains("'#00D7E8'")));
  });
}
