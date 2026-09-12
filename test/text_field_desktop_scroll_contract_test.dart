import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('global scroll behavior leaves desktop mouse drags to text selection', () {
    final source = File('lib/ui_foundation.dart').readAsStringSync();

    final dragDevicesBlock = RegExp(
      r'Set<ui\.PointerDeviceKind> get dragDevices => const \{([\s\S]*?)\};',
    ).firstMatch(source);

    expect(dragDevicesBlock, isNotNull);
    final devices = dragDevicesBlock!.group(1)!;
    expect(devices, isNot(contains('ui.PointerDeviceKind.mouse')));
    expect(devices, contains('ui.PointerDeviceKind.trackpad'));
  });

  test('EditableText internal scrolling is clamped and has no elastic wrapper', () {
    final source = File('lib/ui_foundation.dart').readAsStringSync();

    expect(source, contains('bool _insideEditableText(BuildContext context)'));
    expect(
      source,
      contains('if (_insideEditableText(context)) return const ClampingScrollPhysics();'),
    );
    expect(
      source,
      contains('if (_insideEditableText(context)) return child;'),
    );
  });
}
