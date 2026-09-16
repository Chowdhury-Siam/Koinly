import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Settings exposes validated Worker profile as an in-app administration screen', () {
    final source = File('lib/main.dart').readAsStringSync();
    final profile = File('lib/profile/worker_profile_ui.dart').readAsStringSync();

    expect(source, contains("title: 'Profile'"));
    expect(source, contains('state.selfHostedSyncEndpointValidated && state.selfHostedSyncApiBaseUrl.trim().isNotEmpty'));
    expect(source, contains('selfHostedSyncEndpointValidated = true;'));
    expect(source, contains("prefs.setBool('selfHostedSyncEndpointValidated', true)"));
    expect(source, contains('builder: (_) => WorkerProfileScreen('));
    expect(source, contains('suggestedUsername: state.syncAccountUsername'));

    expect(profile, contains("_uri('/profile/api/login')"));
    expect(profile, contains("_uri('/profile/api/accounts?page=1')"));
    expect(profile, contains("'/profile/api/accounts/\$userId/username'"));
    expect(profile, contains("'/profile/api/accounts/\$userId/password'"));
    expect(profile, contains("title: 'Administrator login'"));
    expect(profile, contains("label: const Text('Create account')"));
    expect(profile, contains("label: const Text('Change username')"));
  });
}
