import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('center popups consume Android back while the keyboard is visible', () {
    final app = File('lib/main.dart').readAsStringSync();
    final frameStart = app.indexOf('class _KoinlyPopupFrame extends StatelessWidget');
    final contentStart = app.indexOf('class KoinlyPopupContent extends StatelessWidget');

    expect(frameStart, greaterThanOrEqualTo(0));
    expect(contentStart, greaterThan(frameStart));

    final frame = app.substring(frameStart, contentStart);
    expect(frame, contains('final keyboardVisible = media.viewInsets.bottom > 0;'));
    expect(frame, contains('return PopScope<Object?>('));
    expect(frame, contains('canPop: !keyboardVisible'));
    expect(frame, contains('onPopInvokedWithResult: (didPop, result)'));
    expect(frame, contains('if (didPop || !keyboardVisible) return;'));
    expect(frame, contains('FocusManager.instance.primaryFocus?.unfocus();'));
  });

  test('transaction editor uses the guarded center-popup route', () {
    final app = File('lib/main.dart').readAsStringSync();
    final editorStart = app.indexOf('Future<void> showTransactionEditor(');
    final stateStart = app.indexOf('class TransactionEditor extends StatefulWidget', editorStart);

    expect(editorStart, greaterThanOrEqualTo(0));
    expect(stateStart, greaterThan(editorStart));

    final editorLauncher = app.substring(editorStart, stateStart);
    expect(editorLauncher, contains('showKoinlyPopup<void>('));
    expect(editorLauncher, contains('child: TransactionEditor('));
  });
}
