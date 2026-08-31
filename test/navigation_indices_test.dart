import 'package:flutter_test/flutter_test.dart';
import 'package:koinly/app_config.dart';

void main() {
  test('primary navigation keeps Loans in the middle slot', () {
    expect(kHomeTabIndex, 0);
    expect(kAnalysisTabIndex, 1);
    expect(kLoansTabIndex, 2);
    expect(kTransactionTabIndex, 3);
    expect(kCategoriesTabIndex, 4);
  });
}
