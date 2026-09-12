import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('app and worker website use the SF Pro font stack', () {
    final main = File('lib/main.dart').readAsStringSync();
    final worker = File('cloud/worker/src/profile.ts').readAsStringSync();
    final pubspec = File('pubspec.yaml').readAsStringSync();

    expect(main, contains("fontFamily: '.SF Pro Display'"));
    expect(main, contains("'.SF Pro Display'"));
    expect(main, contains("'SF Pro Text'"));
    expect(worker, contains('"SF Pro Display","SF Pro Text",-apple-system,BlinkMacSystemFont'));
    expect(pubspec, contains('version: 1.0.1116+160'));
  });
}
