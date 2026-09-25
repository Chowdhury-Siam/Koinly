import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';

const app = readFileSync(new URL('../../../lib/main.dart', import.meta.url), 'utf8');
const worker = readFileSync(new URL('../src/index.ts', import.meta.url), 'utf8');

test('notes are uploaded after save and their deletion is synchronized', () => {
  const tables = app.split('static const syncTables = [')[1].split('];')[0];
  assert.match(tables, /'notes'/);
  const save = app.split('Future<void> saveNote(KoinlyNote note) async {')[1].split('Future<void> toggleNoteBookmark')[0];
  assert.match(save, /enqueueTableRow\('notes', note.id\)/);
  assert.match(save, /reload\(queueSync: true\)/);
  const remove = app.split('Future<void> deleteNote(String id) async {')[2].split('Future<void> saveSubscription')[0];
  assert.match(remove, /enqueueDelete\('notes', id\)/);
  assert.ok(remove.indexOf('enqueueDelete') < remove.indexOf('database.deleteNote'));
});

test('existing offline notes migrate with atomic, account-specific one-time adoption', () => {
  const migration = app.split('Future<void> enqueueLegacyNotesForCloudSync(String accountScope) async {')[1].split('Future<void> enqueueDelete')[0];
  assert.match(migration, /database\.transaction/);
  assert.match(migration, /notesSyncBackfillV1:/);
  assert.match(migration, /NOT EXISTS \(\s*SELECT 1 FROM sync_outbox/);
  assert.match(migration, /NOT EXISTS \(\s*SELECT 1 FROM sync_entity_versions/);
  assert.match(migration, /txn\.insert\('sync_state'/);
  assert.match(app, /enqueueLegacyNotesForCloudSync\(/);
  assert.match(app, /if \(entityType == 'notes'\) \{[\s\S]*?txn\.delete\('sync_outbox'/);
  assert.match(app, /if \(entityType == 'notes' && operation == 'delete'\)/);
});

test('Worker cloud backups include the same note entities as device sync', () => {
  const backupTables = worker.split('const telegramBackupEntityTables = [')[1].split('] as const;')[0];
  assert.match(backupTables, /'notes'/);
  assert.match(worker, /telegramBackupEntityTables\.map\(table => \[table, database\[table\]\.length\]\)/);
});
