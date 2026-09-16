import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Settings exposes Worker profile only after a validated Worker URL exists', () {
    final source = File('lib/main.dart').readAsStringSync();

    expect(source, contains("title: 'Profile'"));
    expect(source, contains('state.selfHostedSyncApiBaseUrl.trim().isNotEmpty'));
    expect(source, contains(r"Uri.parse('$baseUrl/profile')"));
    expect(source, contains('mode: LaunchMode.externalApplication'));
    expect(source, contains("'Could not open the Worker profile.'"));
  });
}
