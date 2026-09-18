import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('transaction lists sort by the complete timestamp newest first', () {
    final source = File('lib/main.dart').readAsStringSync();

    expect(source, contains('final byListDateTime = b.listOn.compareTo(a.listOn);'));
    expect(source, contains('final byCreatedTime = b.createdOn.compareTo(a.createdOn);'));
    expect(source, isNot(contains('final byTime = aListOn.compareTo(bListOn);')));
    expect(source, isNot(contains('final byDay = bDay.compareTo(aDay);')));
  });
}
