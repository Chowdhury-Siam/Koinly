import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('multi-device sync uses low-latency foreground timings', () {
    final source = File('lib/main.dart').readAsStringSync();

    expect(source, contains('Duration(milliseconds: 350)'));
    expect(source, contains('Duration(seconds: 3)'));
    expect(source, contains('Duration(milliseconds: 2500)'));
    expect(source, contains('Duration(seconds: 10)'));
    expect(source, contains('Timer(_cloudSyncPushDebounce'));
    expect(source, contains('Timer.periodic(_cloudSyncAutoPullInterval'));
    expect(source, contains('Timer.periodic(_cloudSyncRetryInterval'));
  });
}
