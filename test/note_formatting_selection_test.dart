import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:koinly/main.dart';

Map<String, dynamic> storedNote(NoteRichTextController controller) {
  const prefix = 'KOINLY_RICH_NOTE_V1:';
  final stored = controller.toStoredBody();
  expect(stored, startsWith(prefix));
  return jsonDecode(stored.substring(prefix.length)) as Map<String, dynamic>;
}

List<Map<String, dynamic>> ranges(NoteRichTextController controller) =>
    (storedNote(controller)['styles'] as List)
        .cast<Map<String, dynamic>>();

void main() {
  test('bold and italic apply to the same selected text without collapsing selection', () {
    final note = NoteRichTextController.fromStored('first second');
    addTearDown(note.dispose);

    const selected = TextSelection(baseOffset: 0, extentOffset: 5);
    note.selection = selected;
    note.toggleStyle(NoteInlineStyle.bold);
    expect(note.selection, selected);
    expect(note.isStyleActive(NoteInlineStyle.bold), isTrue);

    // Simulates the selection collapsing when an Android toolbar gains focus.
    note.selection = const TextSelection.collapsed(offset: 5);
    note.toggleStyle(NoteInlineStyle.italic, selectionOverride: selected);
    expect(note.selection, selected);
    expect(note.isStyleActive(NoteInlineStyle.bold), isTrue);
    expect(note.isStyleActive(NoteInlineStyle.italic), isTrue);
    expect(storedNote(note)['text'], 'first second');
    expect(ranges(note), containsAll([
      {'start': 0, 'end': 5, 'style': 'bold'},
      {'start': 0, 'end': 5, 'style': 'italic'},
    ]));

    note.toggleStyle(NoteInlineStyle.bold);
    expect(note.isStyleActive(NoteInlineStyle.bold), isFalse);
    expect(note.isStyleActive(NoteInlineStyle.italic), isTrue);
  });

  test('caret typing style clears when the cursor moves to unformatted text', () {
    final note = NoteRichTextController.fromStored('one two');
    addTearDown(note.dispose);
    note.selection = const TextSelection.collapsed(offset: 0);
    note.toggleStyle(NoteInlineStyle.bold);
    expect(note.isStyleActive(NoteInlineStyle.bold), isTrue);

    note.value = const TextEditingValue(
      text: 'Xone two',
      selection: TextSelection.collapsed(offset: 1),
    );
    expect(ranges(note), contains({'start': 0, 'end': 1, 'style': 'bold'}));

    note.selection = const TextSelection.collapsed(offset: 7);
    expect(note.isStyleActive(NoteInlineStyle.bold), isFalse);
    note.value = const TextEditingValue(
      text: 'Xone twYo',
      selection: TextSelection.collapsed(offset: 8),
    );
    expect(ranges(note), contains({'start': 0, 'end': 1, 'style': 'bold'}));
  });

  test('replacing an unformatted selection does not inherit prior bold word', () {
    final note = NoteRichTextController.fromStored('Bold plain');
    addTearDown(note.dispose);
    note.selection = const TextSelection(baseOffset: 0, extentOffset: 4);
    note.toggleStyle(NoteInlineStyle.bold);
    note.selection = const TextSelection(baseOffset: 5, extentOffset: 10);
    note.value = const TextEditingValue(
      text: 'Bold other',
      selection: TextSelection.collapsed(offset: 10),
    );
    expect(ranges(note), [{'start': 0, 'end': 4, 'style': 'bold'}]);
  });

  test('inserting inside a formatted selection retains the formatting', () {
    final note = NoteRichTextController.fromStored('alpha beta');
    addTearDown(note.dispose);
    note.selection = const TextSelection(baseOffset: 0, extentOffset: 5);
    note.toggleStyle(NoteInlineStyle.italic);
    note.selection = const TextSelection.collapsed(offset: 2);
    note.value = const TextEditingValue(
      text: 'alXpha beta',
      selection: TextSelection.collapsed(offset: 3),
    );
    expect(ranges(note), [{'start': 0, 'end': 6, 'style': 'italic'}]);

    final reopened = NoteRichTextController.fromStored(note.toStoredBody());
    addTearDown(reopened.dispose);
    expect(reopened.text, 'alXpha beta');
    reopened.selection = const TextSelection(baseOffset: 0, extentOffset: 6);
    expect(reopened.isStyleActive(NoteInlineStyle.italic), isTrue);
  });

  test('partially formatted selections are not reported as fully active', () {
    final note = NoteRichTextController.fromStored('left right');
    addTearDown(note.dispose);
    note.selection = const TextSelection(baseOffset: 0, extentOffset: 4);
    note.toggleStyle(NoteInlineStyle.bold);
    note.selection = const TextSelection(baseOffset: 0, extentOffset: 10);
    expect(note.isStyleActive(NoteInlineStyle.bold), isFalse);
  });
}
