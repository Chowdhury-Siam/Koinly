import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('transaction lists default to complete start timestamp newest first', () {
    final source = File('lib/main.dart').readAsStringSync();

    expect(source, contains('final byCreatedTime = b.createdOn.compareTo(a.createdOn);'));
    expect(source, contains('..sort(_compareTransactionDateNewest);'));
    expect(source, contains("orderBy: 'created_on DESC, updated_on DESC, id DESC'"));
    expect(source, isNot(contains('final byListDateTime = b.listOn.compareTo(a.listOn);')));
  });
}
