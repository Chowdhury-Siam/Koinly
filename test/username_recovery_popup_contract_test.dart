import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('self-hosted authentication uses username without in-app password recovery', () {
    final app = File('lib/main.dart').readAsStringSync();
    final api = File('lib/sync_services.dart').readAsStringSync();
    final models = File('lib/sync_models.dart').readAsStringSync();

    expect(app, contains("labelText: 'Username'"));
    expect(app, isNot(contains("Text('Forgot password?')")));
    expect(app, isNot(contains('class _AccountRecoveryPopup')));
    expect(app, isNot(contains('class _RecoveryKeyPopup')));
    expect(app, isNot(contains('recoverSyncAccount(')));
    expect(app, isNot(contains('rotateSyncRecoveryKey()')));
    expect(api, contains("'username': username"));
    expect(api, isNot(contains("'/v1/auth/recover'")));
    expect(api, isNot(contains("'/v1/auth/recovery-key'")));
    expect(models, contains('final String username;'));
    expect(models, isNot(contains('recoveryKey')));
  });

  test('center popup bodies use fixed adaptive content instead of full-card scrolling', () {
    final app = File('lib/main.dart').readAsStringSync();
    final loans = File('lib/loans/loan_sheets.dart').readAsStringSync();
    final profile = File('lib/profile/profile_ui.dart').readAsStringSync();

    expect(app, contains('class KoinlyPopupContent extends StatelessWidget'));
    expect(app, contains('fit: BoxFit.scaleDown'));

    // The only remaining SingleChildScrollView in main.dart belongs to the
    // full onboarding page, not a showKoinlyPopup center dialog.
    expect(RegExp(r'SingleChildScrollView\(').allMatches(app).length, 1);
    expect(loans, isNot(contains('SingleChildScrollView(')));
    expect(profile, isNot(contains('SingleChildScrollView(')));
  });
}
