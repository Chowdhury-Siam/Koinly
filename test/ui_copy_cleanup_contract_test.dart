import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('settings analytics and archive omit removed helper copy', () {
    final main = File('lib/main.dart').readAsStringSync();
    final analytics = File('lib/analytics/analytics.dart').readAsStringSync();
    final ui = '$main\n$analytics';

    for (final removed in <String>[
      'Notification text:',
      'Follow device setting',
      'Bright interface',
      'Low-light interface',
      'Use system behavior',
      'Only today',
      'Current week',
      'Current month',
      'Current year',
      'Everything saved',
      'Everything synchronized',
      'Choose start and end date',
      'Koinly keeps the Google OAuth Client Secret and refresh token encrypted in your Worker. These credentials are configured only on this page.',
      'Telegram Backup, Telegram report, and Google Drive report times must all be at least 5 minutes apart.',
      'Telegram report, Google Drive report, and Telegram Backup times must all be at least 5 minutes apart.',
      'Uploads a .koinlybackup generated from the latest synchronized cloud data.',
      'Generated from the latest data synchronized to your Self-Hosted Worker.',
      'Telegram and Google Drive uploads go directly through your Self-Hosted Sync Worker. Configure both integrations in Settings > Credential.',
      'Detailed report for the selected date filter with comparison, activity, budgets, category breakdowns, and account balances.',
    ]) {
      expect(ui, isNot(contains(removed)), reason: 'Removed helper text should stay out of the UI: $removed');
    }
  });
}
