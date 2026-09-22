import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('saved Worker accounts switch without cross-account uploads', () {
    final app = File('lib/main.dart').readAsStringSync();
    final stores = File('lib/persistence_stores.dart').readAsStringSync();

    expect(stores, contains('class SavedSyncAccount'));
    expect(stores, contains("static const _savedSyncAccountsKey = 'koinly_saved_sync_accounts_v1';"));
    expect(stores, contains('Future<List<SavedSyncAccount>> readSavedSyncAccounts()'));
    expect(stores, contains('Future<void> writeSavedSyncAccounts(List<SavedSyncAccount> accounts)'));

    expect(app, contains('List<SavedSyncAccount> syncAccountConnections = const [];'));
    expect(app, contains('Future<void> switchSyncAccount(SavedSyncAccount account)'));
    expect(app, contains('await _rememberActiveSyncAccount();'));
    expect(app, contains('await _removeSavedSyncAccount(workerUrl: signedOutWorkerUrl, username: signedOutUsername);'));

    final switchStart = app.indexOf('Future<void> switchSyncAccount(SavedSyncAccount account)');
    final syncCurrent = app.indexOf('await syncToCloud(force: true, silent: true);', switchStart);
    final clearLocal = app.indexOf('await _clearSignedOutCloudAccountLocalData();', switchStart);
    final resetTracking = app.indexOf("await database.writeSyncState('serverCursor', '0');", switchStart);
    final pullSelected = app.indexOf('await performMultiDeviceSync(silent: true, pushLocalChanges: false, pullFullCloudCopy: true);', switchStart);
    expect(syncCurrent, greaterThan(switchStart));
    expect(clearLocal, greaterThan(syncCurrent));
    expect(resetTracking, greaterThan(clearLocal));
    expect(pullSelected, greaterThan(resetTracking));
    expect(app.substring(switchStart, pullSelected), isNot(contains('pushLocalChanges: true')));

    expect(app, contains('Cloud accounts'));
    expect(app, contains('Manage Worker accounts'));
    expect(app, contains('WorkerProfileScreen('));
    expect(app, contains("label: Text(active ? 'Active' : 'Switch')"));
  });
}
