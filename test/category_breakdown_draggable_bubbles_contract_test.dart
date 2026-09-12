import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('category breakdown bubbles are draggable and stay inside the chart card', () {
    final source = File('lib/main.dart').readAsStringSync();

    expect(
      source,
      contains(r"key: ValueKey('breakdown-badge-${slices[i].categoryId}')"),
    );
    expect(source, contains('draggable: interactive'));
    expect(source, contains('class _DonutBadgePositioned extends StatefulWidget'));
    expect(source, contains('onPanStart: widget.draggable ? _startDrag : null'));
    expect(source, contains('onPanUpdate: widget.draggable ? _updateDrag : null'));
    expect(source, contains('candidate.dx.clamp(minLeft, maxLeft)'));
    expect(source, contains('candidate.dy.clamp(minTop, maxTop)'));
    expect(source, contains('cursor: SystemMouseCursors.move'));
  });
}
