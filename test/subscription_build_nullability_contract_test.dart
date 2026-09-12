import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('subscription scheduler snapshots nullable processed time before date serialization', () {
    final source = File('lib/subscription_background_service.dart').readAsStringSync();

    expect(source, contains('final processedOn = lastProcessed;'));
    expect(
      source,
      contains("'last_processed_on': processedOn == null ? null : dateToDb(processedOn)"),
    );
    expect(
      source,
      isNot(contains('lastProcessed == null ? null : dateToDb(lastProcessed)')),
    );
  });
}
