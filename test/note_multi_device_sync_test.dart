import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:koinly/data_merge.dart';

void main() {
  test('notes participate in both local writes and the cloud change stream', () {
    final source = File('lib/main.dart').readAsStringSync();
    final syncTables = source
        .split('static const syncTables = [')[1]
        .split('];')[0];
    expect(syncTables, contains("'notes',"));

    final saveNote = source
        .split('Future<void> saveNote(KoinlyNote note) async {')[1]
        .split('Future<void> toggleNoteBookmark')[0];
    expect(saveNote, contains("await database.enqueueTableRow('notes', note.id);"));
    expect(saveNote, contains('await reload(queueSync: true);'));

    final deleteNote = source
        .split('Future<void> deleteNote(String id) async {')[2]
        .split('Future<void> saveSubscription')[0];
    expect(deleteNote, contains("await database.enqueueDelete('notes', id);"));
    expect(deleteNote.indexOf('enqueueDelete'), lessThan(deleteNote.indexOf('database.deleteNote')));
    expect(deleteNote, contains('await reload(queueSync: true);'));
  });

  test('pre-upgrade notes are queued only once without overwriting tracked notes', () {
    final source = File('lib/main.dart').readAsStringSync();
    final migration = source
        .split('Future<void> enqueueLegacyNotesForCloudSync(String accountScope) async {')[1]
        .split('Future<void> enqueueDelete')[0];
    expect(migration, contains('await database.transaction((txn) async {'));
    expect(migration, contains('notesSyncBackfillV1:'));
    expect(migration, contains('FROM notes AS n'));
    expect(migration, contains("o.entity_type = 'notes'"));
    expect(migration, contains("v.entity_type = 'notes'"));
    expect(migration, contains("'entity_type': 'notes'"));
    expect(migration, contains("await txn.insert('sync_state'"));
    expect(source, contains('await database.enqueueLegacyNotesForCloudSync('));
    expect(source, contains('remotelyDeletedNoteIds.contains(entityId)'));
  });

  test('rich-text note payloads are preserved during a two-device merge', () {
    const richBody = 'KOINLY_RICH_NOTE_V1:{"text":"Bold and plain","styles":[{"start":0,"end":4,"style":"bold"}]}';
    final deviceA = <String, dynamic>{
      'notes': [
        {'id': 'note-1', 'title': 'First', 'body': richBody, 'bookmarked': 1,
         'draft': 0, 'created_on': 100, 'updated_on': 200},
      ],
    };
    final deviceB = <String, dynamic>{
      'notes': [
        {'id': 'note-1', 'title': 'Old title', 'body': 'old', 'bookmarked': 0,
         'draft': 0, 'created_on': 100, 'updated_on': 150},
        {'id': 'note-2', 'title': 'Second', 'body': 'Plain text',
         'bookmarked': 0, 'draft': 1, 'created_on': 180, 'updated_on': 180},
      ],
    };
    final merged = mergeFinanceDatabasePayloads(deviceB, deviceA);
    final notes = (merged.database['notes'] as List).cast<Map>();
    expect(notes.length, 2);
    expect(notes.firstWhere((note) => note['id'] == 'note-1')['body'], richBody);
    expect(notes.firstWhere((note) => note['id'] == 'note-1')['bookmarked'], 1);
    expect(notes.firstWhere((note) => note['id'] == 'note-2')['draft'], 1);
  });

  test('cloud backups and linked version metadata include notes', () {
    final worker = File('cloud/worker/src/index.ts').readAsStringSync();
    final backupTables = worker
        .split('const telegramBackupEntityTables = [')[1]
        .split('] as const;')[0];
    expect(backupTables, contains("'notes',"));
    expect(worker, contains('for (const table of telegramBackupEntityTables) database[table] = [];'));
  });
}
