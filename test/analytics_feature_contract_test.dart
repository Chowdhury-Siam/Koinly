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
    expect(analytics, contains("label: const Text('Share PDF')"));
    expect(analytics, contains('AnalyticsPdfService.build'));
    expect(analytics, contains('Share.shareXFiles'));
    expect(analytics, contains("label: const Text('Upload Telegram')"));
    expect(analytics, contains("label: const Text('Upload Drive')"));
    expect(analytics, contains('class AnalyticsUploadSettingsScreen'));
    expect(analytics, contains('saveGoogleDriveAnalyticsSettings'));
    expect(analytics, contains('uploadAnalyticsPdfToTelegram'));
    expect(analytics, contains('uploadAnalyticsPdfToGoogleDrive'));

    expect(pubspec, contains('pdf: ^3.13.0'));
    expect(pubspec, contains('version: 1.0.1129+173'));
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
