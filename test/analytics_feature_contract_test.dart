import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('settings exposes analytics with all summary periods and PDF export', () {
    final main = File('lib/main.dart').readAsStringSync();
    final analytics = File('lib/analytics/analytics.dart').readAsStringSync();
    final pubspec = File('pubspec.yaml').readAsStringSync();

    expect(main, contains("title: 'Analytics'"));
    expect(main, contains('const AnalyticsScreen()'));
    expect(main, contains("part 'analytics/analytics.dart';"));

    expect(analytics, contains('enum AnalyticsPeriod { daily, weekly, monthly, yearly }'));
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
    expect(analytics, contains('static Future<Uint8List> _buildTransactionHistory'));
    expect(analytics, contains("pw.Text('Transaction ledger'"));
    expect(analytics, contains("pw.Text('Compared with previous period'"));
    expect(analytics, isNot(contains("const SectionHeader('Compared with previous period')")));
    expect(analytics, isNot(contains("const SectionHeader('Activity')")));
    expect(analytics, isNot(contains("const SectionHeader('Budgets')")));
    expect(analytics, isNot(contains("const SectionHeader('Top expense categories')")));
    expect(analytics, isNot(contains("const SectionHeader('Top income categories')")));
    expect(analytics, isNot(contains("const SectionHeader('Current account snapshot')")));

    expect(pubspec, contains('pdf: ^3.13.0'));
    expect(pubspec, contains('version: 1.0.1133+177'));
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
