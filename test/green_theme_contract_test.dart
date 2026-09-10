import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('shared visual system stays emerald and green-cast', () {
    final config = File('lib/app_config.dart').readAsStringSync();
    final mainSource = File('lib/main.dart').readAsStringSync();

    expect(config, contains('kSleekAccent = Color(0xFF10B981)'));
    expect(config, contains('kSleekBackground = Color(0xFF06110D)'));
    expect(config, contains('kSleekSurface = Color(0xFF0B1914)'));
    expect(config, contains("kSleekAccentHex = '#10B981'"));
    expect(mainSource, contains('surfaceContainerLow: kSleekSurfaceLow'));
    expect(mainSource, contains('surfaceContainer: kSleekSurfaceContainer'));
    expect(mainSource, contains('outlineVariant: kSleekOutlineVariant'));
    expect(mainSource, contains('colors: [Color(0xFF071711), kSleekBackground, Color(0xFF091914)]'));
    expect(mainSource, isNot(contains('0xFF00D7E8')));
    expect(mainSource, isNot(contains("'#00D7E8'")));
  });
}
