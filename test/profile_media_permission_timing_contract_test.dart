import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('profile media permission is requested only from the profile upload flow', () {
    final app = File('lib/main.dart').readAsStringSync();
    final profileUi = File('lib/profile/profile_ui.dart').readAsStringSync();

    expect(app, isNot(contains('ProfileMediaPermissionGate')));
    expect(profileUi, isNot(contains('ProfileMediaPermissionGate')));
    expect(profileUi, contains('Future<void> pickAndSaveProfileMedia'));
    expect(profileUi, contains('requestProfileMediaPermissionFlow(context, state)'));
    expect(profileUi, contains('state.profileMediaPermissions.request()'));
    expect(profileUi, contains('FilePicker.platform.pickFiles'));
  });
}
