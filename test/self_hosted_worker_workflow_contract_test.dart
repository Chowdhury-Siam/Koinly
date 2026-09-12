import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('fork pushes automatically deploy the self-hosted Worker', () {
    final workflow =
        File('.github/workflows/deploy-sync-worker.yml').readAsStringSync();

    expect(workflow, contains('push:'));
    expect(workflow, contains('      - main'));
    expect(workflow, contains('      - master'));
    expect(
      workflow,
      contains(
        "if: github.event_name == 'workflow_dispatch' || github.repository != 'Chowdhury-Siam/Koinly'",
      ),
    );
    expect(workflow, isNot(contains('      - "cloud/worker/**"')));
    expect(
      workflow,
      isNot(contains('      - ".github/workflows/deploy-sync-worker.yml"')),
    );
  });

  test('deployment health waits for the current Worker capability contract', () {
    final workflow =
        File('.github/workflows/deploy-sync-worker.yml').readAsStringSync();

    expect(workflow, contains('health_ready=0'));
    expect(workflow, contains('for attempt in {1..18}; do'));
    expect(workflow, contains('.profileMediaSyncAvailable == true'));
    expect(workflow, contains('the newly deployed capability contract is not ready yet'));
    expect(workflow, contains('health_ready=1'));
  });
}
