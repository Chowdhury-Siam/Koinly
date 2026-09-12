import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('transaction quick menu stacks subscription above plan with staggered motion', () {
    final source = File('lib/main.dart').readAsStringSync();

    final subscription = source.indexOf("heroTag: 'transactionSubscriptionFab'");
    final plan = source.indexOf("heroTag: 'transactionPlanFab'");

    expect(subscription, greaterThanOrEqualTo(0));
    expect(plan, greaterThan(subscription));
    expect(source, contains("((raw - .06) / .54)"));
    expect(source, contains("((raw - .46) / .54)"));
    expect(source, contains('Reversing the same controller naturally closes them in reverse'));
  });
}
