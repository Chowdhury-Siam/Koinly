import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('multi-device sync uses realtime-first low-latency timings', () {
    final source = File('lib/main.dart').readAsStringSync();

    expect(source, contains('Duration(milliseconds: 120)'));
    expect(source, contains('_cloudSyncRealtimeFallbackInterval = Duration(seconds: 20)'));
    expect(source, contains('_cloudSyncDisconnectedFallbackInterval = Duration(seconds: 3)'));
    expect(source, contains('Duration(milliseconds: 750)'));
    expect(source, contains('Duration(seconds: 5)'));
    expect(source, contains('Timer(_cloudSyncPushDebounce'));
    expect(source, contains('Timer.periodic(interval'));
    expect(source, contains('Timer.periodic(_cloudSyncRetryInterval'));
  });
}
