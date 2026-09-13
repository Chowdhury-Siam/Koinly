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
    expect(app, contains('SelfHostedTelegramBackupScreen'));
    expect(app, contains("title: 'Telegram backup'"));
    expect(app, contains('Automatic Telegram backup'));
    expect(app, contains('Test bot and destination'));
    expect(app, contains('Upload backup now'));
    expect(app, contains('TelegramBackupFrequency.daily'));
    expect(app, contains('TelegramBackupFrequency.weekly'));
    expect(app, contains('TelegramBackupFrequency.monthly'));
    expect(app, isNot(contains('Self-hosted Sync Worker only')));
    expect(app, isNot(contains('The self-hosted Worker creates a .koinlybackup from the cloud copy and uploads it to your Telegram group or channel.')));
    expect(app, isNot(contains('Add the bot to the target group/channel. For a channel, make the bot an administrator with permission to post messages. The bot token is encrypted by your Worker before it is stored in Turso.')));
    expect(app, isNot(contains('Schedule uses this device timezone')));

    expect(api, contains('/v1/telegram-backup/settings'));
    expect(api, contains('/v1/telegram-backup/test'));
    expect(api, contains('/v1/telegram-backup/send-now'));

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
    expect(selfHostedWrangler, contains('crons = ["*/5 * * * *"]'));
    expect(workflow, contains('--config wrangler.self-hosted.toml'));
    expect(workflow, contains('.telegramBackupAvailable == true'));
  });
}
