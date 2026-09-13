import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('settings exposes date-filtered analytics and PDF export', () {
    final main = File('lib/main.dart').readAsStringSync();
    final analytics = File('lib/analytics/analytics.dart').readAsStringSync();
    final pubspec = File('pubspec.yaml').readAsStringSync();

    expect(main, contains("title: 'Analytics'"));
    expect(main, contains('const AnalyticsScreen()'));
    expect(main, contains("part 'analytics/analytics.dart';"));

    expect(analytics, contains('DateRangeType dateFilter = DateRangeType.thisMonth'));
    expect(analytics, contains("title: 'Choose Date Filter'"));
    expect(analytics, contains('DateRangeType.allTime'));
    expect(analytics, contains('class AnalyticsSnapshot'));
    expect(analytics, contains("title: 'Analytics'"));
    expect(analytics, contains("label: const Text('Download PDF')"));
    expect(analytics, isNot(contains("label: const Text('Share PDF')")));
    expect(analytics, contains('AnalyticsPdfService.build'));
    expect(analytics, isNot(contains('shareAnalyticsPdf(')));
    expect(analytics, contains("label: const Text('Upload Telegram')"));
    expect(analytics, contains("label: const Text('Upload Drive')"));
    expect(analytics, contains('class AnalyticsUploadSettingsScreen'));
    expect(analytics, contains('saveGoogleDriveAnalyticsSettings'));
    expect(analytics, contains('uploadAnalyticsPdfToTelegram'));
    expect(analytics, contains('uploadAnalyticsPdfToGoogleDrive'));
    expect(analytics, contains('enum AnalyticsPdfVariant { summary, transactionHistory }'));
    expect(analytics, contains("label: 'Transaction history'"));
    expect(analytics, contains('static Future<Uint8List> _buildTransactionHistory(AppController state, AnalyticsSnapshot snapshot)'));
    expect(analytics, contains('List<MoneyTransaction>.of(snapshot.transactions)'));
    expect(analytics, contains('Transaction history uses the selected date filter. Choose All Time'));
    expect(analytics, isNot(contains('does not use the selected analytics period')));
    expect(analytics, contains("tooltip: 'Telegram bot settings'"));
    expect(analytics, contains('Icons.smart_toy_rounded'));
    expect(analytics, contains("pw.Text('Transaction ledger'"));
    expect(analytics, contains("pw.Text('Compared with previous period'"));
    expect(analytics, isNot(contains("const SectionHeader('Compared with previous period')")));
    expect(analytics, isNot(contains("const SectionHeader('Activity')")));
    expect(analytics, isNot(contains("const SectionHeader('Budgets')")));
    expect(analytics, isNot(contains("const SectionHeader('Top expense categories')")));
    expect(analytics, isNot(contains("const SectionHeader('Top income categories')")));
    expect(analytics, isNot(contains("const SectionHeader('Current account snapshot')")));

    expect(pubspec, contains('pdf: ^3.13.0'));
    expect(pubspec, contains('version: 1.0.1136+180'));
    expect(analytics, contains('Automatic Telegram PDF upload'));
    expect(analytics, contains('Automatic Google Drive PDF upload'));
    expect(analytics, contains('must be at least 5 minutes apart'));
    expect(analytics, contains('AnalyticsPdfScheduleDateFilter.allTime'));
    expect(analytics, contains('saveAnalyticsPdfSchedule'));
    expect(main, contains('loadAnalyticsPdfSchedules'));
    expect(main, contains('saveAnalyticsPdfSchedule'));
  });

  test('static category badges keep no obsolete orbit fallback state', () {
    final source = File('lib/main.dart').readAsStringSync();
    final start = source.indexOf('class _DonutBadgePositioned');
    final end = source.indexOf('class _DonutPercentBadge', start);
    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));
    final helper = source.substring(start, end);

    expect(helper, contains('required this.center'));
    expect(helper, isNot(contains('angleDegrees')));
    expect(helper, isNot(contains('verticalNudge')));
    expect(helper, isNot(contains('centerOverride')));
  });
}
