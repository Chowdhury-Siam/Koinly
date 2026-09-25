import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Note editor toolbar excludes U and Quote without affecting saved note styles', () {
    final main = File('lib/main.dart').readAsStringSync();
    final bar = main.split('class _NoteFormatBar extends StatelessWidget {').last
        .split('class _NoteDivider extends StatelessWidget {').first;
    final editorWiring = main.split('builder: (context, _, __) => _NoteFormatBar(').last
        .split('onUndo: _undoBody,').first;

    expect(bar, isNot(contains("label: 'U'")));
    expect(bar, isNot(contains('format_quote_rounded')));
    expect(bar, isNot(contains('onUnderline')));
    expect(bar, isNot(contains('onQuote')));
    expect(editorWiring, isNot(contains('onUnderline:')));
    expect(editorWiring, isNot(contains('onQuote:')));
    for (final control in [
      "label: 'B'", "label: 'I'", "label: 'S'", 'Icons.border_color_rounded',
      'Icons.link_rounded', 'Icons.format_list_bulleted_rounded',
      'Icons.code_rounded', 'Icons.undo_rounded', 'Icons.redo_rounded',
    ]) {
      expect(bar, contains(control));
    }
    // Legacy rich-text notes must still decode and render underline styling.
    expect(main, contains('enum NoteInlineStyle { bold, italic, underline,'));
    expect(main, contains('styles.contains(NoteInlineStyle.underline)'));
  });
}
