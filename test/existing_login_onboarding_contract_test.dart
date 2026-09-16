import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('existing account login completes onboarding in the controller', () {
    final source = File('lib/main.dart').readAsStringSync();

    expect(
      source,
      contains('await _mergeAfterExistingAccountAuth(preferCloudData: preferCloudData);'),
    );
    expect(
      source,
      contains('if (!onboardingCompleted) {\n          await completeOnboarding();'),
    );
  });

  test('persisted existing session repairs stale onboarding flag', () {
    final source = File('lib/main.dart').readAsStringSync();

    expect(
      source,
      contains("cloudSyncEnabled &&\n        syncAccountUsername.trim().isNotEmpty &&\n        !newSyncAccountAwaitingSetupChoice"),
    );
    expect(source, contains("await prefs.setBool('onboardingCompleted', true);"));
  });
}
