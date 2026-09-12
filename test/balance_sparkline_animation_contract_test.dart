import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('net balance sparkline keeps the stronger animated treatment', () {
    final source = File('lib/main.dart').readAsStringSync();

    expect(source, contains('Duration(milliseconds: 2400)'));
    expect(source, contains('primaryWave = math.sin(phase + index * .78) * .30'));
    expect(source, contains('secondaryWave = math.sin(phase * 1.55 - index * .44) * .10'));
    expect(source, contains('final lineOpacity = reduceMotion ? 1.0 : .78 + pulse * .22'));
    expect(source, contains('final lineWidth = reduceMotion ? 3.0 : 3.1 + pulse * .9'));
    expect(source, contains('MediaQuery.of(context).disableAnimations'));
  });
}
