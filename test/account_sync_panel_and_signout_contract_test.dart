import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('signed-in Worker panel is animated and sign-out keeps cloud data safe', () {
    final source = File('lib/main.dart').readAsStringSync();
    final worker = File('cloud/worker/src/index.ts').readAsStringSync();

    expect(source, contains('late bool _workerCardExpanded;'));
    expect(source, contains('_workerCardExpanded = !state.cloudSyncEnabled;'));
    expect(source, contains("tooltip: _workerCardExpanded ? 'Hide Worker settings' : 'Show Worker settings'"));
    expect(source, contains("key: const ValueKey('sync-worker-card-visible')"));
    expect(source, contains("key: ValueKey('sync-worker-card-hidden')"));
    expect(source, contains('duration: const Duration(milliseconds: 520)'));
    expect(source, contains('SizeTransition('));
    expect(source, contains('FadeTransition(opacity: curved, child: child)'));

    expect(source, contains('String get cloudflareWorkerDisplayName'));
    expect(source, contains("normalizedHost.endsWith('.workers.dev')"));
    expect(source, contains('signedIn ? state.cloudflareWorkerDisplayName : state.cloudSyncStatusText'));

    expect(source, contains("title: const Text('Keep cloud data on this device?')"));
    expect(source, contains("child: const Text('No, clear local data')"));
    expect(source, contains("child: const Text('Yes, keep data')"));
    expect(source, contains('actionsAlignment: MainAxisAlignment.center'));
    expect(source, contains('width: actionWidth'));
    expect(source, contains('crossAxisAlignment: CrossAxisAlignment.stretch'));
    expect(source, contains('minimumSize: const Size.fromHeight(52)'));
    expect(source, contains('Future<void> logoutSyncAccount({bool keepLocalData = true})'));
    expect(source, contains('if (!keepLocalData) {'));
    expect(source, contains('await _clearSignedOutCloudAccountLocalData();'));
    expect(source, contains('await database.clearFinanceDataForRemoteLogin();'));
    expect(source, contains('await _clearLocalProfileMedia(clearRemoteTracking: true);'));

    // Server logout only revokes the current refresh token. It must not delete
    // account finance rows when the device chooses to clear its local copy.
    expect(worker, contains("UPDATE refresh_tokens SET revoked_at = ? WHERE user_id = ? AND token_hash = ?"));
  });

  test('saved Worker accounts can switch by replacing local data from cloud', () {
    final source = File('lib/main.dart').readAsStringSync();
    final models = File('lib/sync_models.dart').readAsStringSync();
    final stores = File('lib/persistence_stores.dart').readAsStringSync();

    expect(models, contains('class SyncAccountProfile'));
    expect(stores, contains('readProfileAccessToken'));
    expect(stores, contains('writeProfileTokens'));
    expect(source, contains('List<SyncAccountProfile> syncAccountProfiles = [];'));
    expect(source, contains('Future<void> switchSyncAccountProfile(SyncAccountProfile profile)'));
    expect(source, contains('await _replaceLocalDataFromActiveCloudAccount();'));
    expect(source, contains('await _clearSignedOutCloudAccountLocalData();'));
    expect(source, contains('pushLocalChanges: false'));
    expect(source, contains('pullFullCloudCopy: true'));
    expect(source, contains("Text('Saved sync accounts'"));
    expect(source, contains("child: const Text('Switch')"));
  });
}
