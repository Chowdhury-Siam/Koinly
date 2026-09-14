import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Archive owns Telegram backup scheduling while Credentials owns bot configuration', () {
    final app = File('lib/main.dart').readAsStringSync();
    final analytics = File('lib/analytics/analytics.dart').readAsStringSync();
    final api = File('lib/sync_services.dart').readAsStringSync();
    final worker = File('cloud/worker/src/index.ts').readAsStringSync();
    final schema = File('cloud/worker/schema.sql').readAsStringSync();
    final workflow = File('.github/workflows/deploy-sync-worker.yml').readAsStringSync();
    final selfHostedWrangler = File('cloud/worker/wrangler.self-hosted.toml').readAsStringSync();

    expect(app, contains("title: 'Archive'"));
    expect(app, contains("title: 'Cloud'"));
    expect(app, contains('SelfHostedTelegramBackupScreen'));
    expect(app, isNot(contains("Text('Telegram destination'")));
    expect(app, isNot(contains("label: const Text('Open Credential')")));
    expect(app, isNot(contains("tooltip: 'Telegram backup'")));
    expect(app, isNot(contains('must all be at least 5 minutes apart')));
    expect(app, contains('Upload backup now'));
    expect(app, contains('TelegramBackupFrequency.daily'));
    expect(app, contains('TelegramBackupFrequency.weekly'));
    expect(app, contains('TelegramBackupFrequency.monthly'));

    expect(analytics, contains("title: 'Credential'"));
    expect(analytics, contains("labelText: _telegram.tokenConfigured ? 'Bot token (saved)' : 'Bot token'"));
    expect(analytics, contains("labelText: 'Group or channel Chat ID'"));
    expect(analytics, contains("labelText: 'Google OAuth Client ID'"));
    expect(analytics, contains("labelText: 'Google OAuth Client Secret'"));
    expect(analytics, contains("labelText: 'Google Drive Folder ID (optional)'"));
    expect(analytics, contains('Telegram credentials saved.'));
    expect(analytics, contains("title: 'Cloud'"));

    final credentialsStart = analytics.indexOf('class CredentialsScreen');
    final cloudBackupStart = analytics.indexOf('class CloudBackupScreen');
    expect(credentialsStart, greaterThanOrEqualTo(0));
    expect(cloudBackupStart, greaterThan(credentialsStart));
    final credentialsUi = analytics.substring(credentialsStart, cloudBackupStart);
    final analyticsOutsideCredentials = analytics.substring(0, credentialsStart) + analytics.substring(cloudBackupStart);
    for (final field in [
      "labelText: _telegram.tokenConfigured ? 'Bot token (saved)' : 'Bot token'",
      "labelText: 'Group or channel Chat ID'",
      "labelText: 'Google OAuth Client ID'",
      "labelText: 'Google OAuth Client Secret'",
      "labelText: 'Google Drive Folder ID (optional)'",
    ]) {
      expect(credentialsUi, contains(field));
      expect(analyticsOutsideCredentials, isNot(contains(field)));
      expect(app, isNot(contains(field)));
    }

    expect(worker, contains('Automatic uploads must be at least 5 minutes apart'));
    expect(worker, contains("readAnalyticsPdfSchedule(db, auth.userId, 'telegram')"));
    expect(api, contains('/v1/telegram-backup/settings'));
    expect(api, contains('/v1/telegram-backup/test'));
    expect(api, contains('/v1/telegram-backup/send-now'));
    expect(api, contains('/v1/google-drive-backup/settings'));
    expect(api, contains('/v1/google-drive-backup/send-now'));
    expect(worker, contains('sendDocument'));
    expect(worker, contains('telegram_backup_settings'));
    expect(worker, contains('telegramBackupFinanceRecordCount(database) === 0'));
    expect(worker, contains('finance_record_count'));
    expect(worker, contains('FROM sync_changes, last_reset'));
    expect(worker, contains("registrationMode: 'first-user'"));
    expect(app, contains('await state.syncToCloud(force: true);'));
    expect(app, contains('while (settlePass < 4 && await database.pendingSyncOperationCount() > 0)'));
    expect(app, contains('serverVersion == 0 || currentRow == null'));
    expect(app, contains("await database.writeSyncState('serverCursor', '0');"));
    expect(app, contains('This backup contains no finance records.'));
    expect(schema, contains('CREATE TABLE IF NOT EXISTS telegram_backup_settings'));
    expect(schema, contains('CREATE TABLE IF NOT EXISTS google_drive_backup_settings'));
    expect(worker, contains("label: 'Google Drive backup'"));
    expect(selfHostedWrangler, contains('crons = ["*/5 * * * *"]'));
    expect(workflow, contains('--config wrangler.self-hosted.toml'));
    expect(workflow, contains('.telegramBackupAvailable == true'));
  });
}
