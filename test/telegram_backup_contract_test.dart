import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('self-hosted Account & sync exposes Telegram backup configuration', () {
    final app = File('lib/main.dart').readAsStringSync();
    final api = File('lib/sync_services.dart').readAsStringSync();
    final worker = File('cloud/worker/src/index.ts').readAsStringSync();
    final schema = File('cloud/worker/schema.sql').readAsStringSync();
    final workflow = File('.github/workflows/deploy-sync-worker.yml').readAsStringSync();
    final selfHostedWrangler = File('cloud/worker/wrangler.self-hosted.toml').readAsStringSync();

    expect(app, contains("tooltip: 'Telegram backup'"));
    expect(app, contains('if (_useCustomCloudSync)'));
    expect(app, contains('SelfHostedTelegramBackupScreen'));
    expect(app, contains("title: 'Telegram backup'"));
    expect(app, contains('Automatic Telegram backup'));
    expect(app, contains('Test bot and destination'));
    expect(app, contains('Upload backup now'));
    expect(app, contains('TelegramBackupFrequency.daily'));
    expect(app, contains('TelegramBackupFrequency.weekly'));
    expect(app, contains('TelegramBackupFrequency.monthly'));

    expect(api, contains('/v1/telegram-backup/settings'));
    expect(api, contains('/v1/telegram-backup/test'));
    expect(api, contains('/v1/telegram-backup/send-now'));

    expect(worker, contains("registrationMode(env) !== 'first-user'"));
    expect(worker, contains('sendDocument'));
    expect(worker, contains('telegram_backup_settings'));
    expect(schema, contains('CREATE TABLE IF NOT EXISTS telegram_backup_settings'));
    expect(selfHostedWrangler, contains('crons = ["*/5 * * * *"]'));
    expect(workflow, contains('--config wrangler.self-hosted.toml'));
    expect(workflow, contains('.telegramBackupAvailable == true'));
  });
}
