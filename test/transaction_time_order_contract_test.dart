import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('transaction lists keep newest day first and earlier time first within a day', () {
    final source = File('lib/main.dart').readAsStringSync();

    expect(source, contains('final aDay = DateTime(aListOn.year, aListOn.month, aListOn.day);'));
    expect(source, contains('final bDay = DateTime(bListOn.year, bListOn.month, bListOn.day);'));
    expect(source, contains('final byDay = bDay.compareTo(aDay);'));
    expect(source, contains('final byTime = aListOn.compareTo(bListOn);'));
    expect(source, isNot(contains('final byListDate = b.listOn.compareTo(a.listOn);')));
  });
}
