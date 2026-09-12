import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('new loan can choose which account gives or receives the principal', () {
    final sheet = File('lib/loans/loan_sheets.dart').readAsStringSync();
    final controller = File('lib/loans/loan_controller_part.dart').readAsStringSync();

    expect(sheet, contains("String? accountId;"));
    expect(sheet, contains("'Give from account'"));
    expect(sheet, contains("'Receive into account'"));
    expect(sheet, contains("title: direction == LoanDirection.lent"));
    expect(sheet, contains('final movementAccountId = accountId;'));
    expect(sheet, contains('accountId: movementAccountId'));
    expect(controller, contains('accountId == null || accountId.isEmpty ? linked.fromAccountId : accountId'));
  });
}
