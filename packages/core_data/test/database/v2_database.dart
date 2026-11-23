import 'package:drift/drift.dart';
import 'package:drift/native.dart';

/// Base SQLite en memoire au format du schema v2 (tel que fusionne le
/// 2026-11-22), avec des donnees, pour tester la migration 2 -> 3.
///
/// DDL fige : copie de ce que Drift creait pour le schema v2 (sqlite_master
/// d'une base v2 neuve). Ne pas le deriver du code courant, qui est v3.
///
/// [extraStatements] s'executent apres les donnees, avant de fixer
/// `user_version` a 2 : ils simulent une migration 2 -> 3 deja (en partie)
/// passee.
QueryExecutor v2DatabaseWithData({
  List<String> extraStatements = const <String>[],
}) {
  return NativeDatabase.memory(
    // ponytail: type `Database` de package:sqlite3, non dependance directe.
    // ignore: always_specify_types
    setup: (raw) {
      kV2Schema.forEach(raw.execute);
      kV2Rows.forEach(raw.execute);
      extraStatements.forEach(raw.execute);
      raw.execute('PRAGMA user_version = 2');
    },
  );
}

/// Schema v2 complet, dans l'ordre de creation.
const List<String> kV2Schema = <String>[
  'CREATE TABLE "sessions" ("id" TEXT NOT NULL, "title" TEXT NOT NULL, '
      '"created_at" TEXT NOT NULL, "updated_at" TEXT NOT NULL, '
      '"duration_seconds" INTEGER NULL, "status" TEXT NOT NULL, '
      '"calendar_event_id" TEXT NULL, "calendar_event_title" TEXT NULL, '
      '"attendees" TEXT NULL, PRIMARY KEY ("id"))',
  'CREATE TABLE "transcript_segments" ("id" TEXT NOT NULL, '
      '"session_id" TEXT NOT NULL REFERENCES sessions (id), '
      '"source" TEXT NOT NULL, "text_content" TEXT NOT NULL, '
      '"timestamp_ms" INTEGER NOT NULL, "created_at" TEXT NOT NULL, '
      '"speaker" TEXT NULL, PRIMARY KEY ("id"))',
  'CREATE TABLE "summaries" ("id" TEXT NOT NULL, '
      '"session_id" TEXT NOT NULL REFERENCES sessions (id), '
      '"content" TEXT NOT NULL, "model" TEXT NOT NULL, '
      '"created_at" TEXT NOT NULL, PRIMARY KEY ("id"))',
  'CREATE TABLE "detected_questions" ("id" TEXT NOT NULL, '
      '"session_id" TEXT NOT NULL REFERENCES sessions (id), '
      '"segment_id" TEXT NULL, "question" TEXT NOT NULL, '
      '"timestamp_ms" INTEGER NOT NULL, "answer" TEXT NULL, '
      '"answer_model" TEXT NULL, "sources" TEXT NULL, '
      '"created_at" TEXT NOT NULL, PRIMARY KEY ("id"))',
  'CREATE TABLE "documents" ("id" TEXT NOT NULL, "title" TEXT NOT NULL, '
      '"path" TEXT NOT NULL, "added_at" TEXT NOT NULL, PRIMARY KEY ("id"))',
  'CREATE TABLE "document_chunks" ("id" TEXT NOT NULL, '
      '"document_id" TEXT NOT NULL REFERENCES documents (id), '
      '"position" INTEGER NOT NULL, "content" TEXT NOT NULL, '
      'PRIMARY KEY ("id"))',
  'CREATE VIRTUAL TABLE document_chunks_fts USING fts5(chunk_id UNINDEXED, '
      "content, tokenize = 'unicode61 remove_diacritics 2')",
  'CREATE TRIGGER document_chunks_ai AFTER INSERT ON document_chunks BEGIN '
      'INSERT INTO document_chunks_fts (chunk_id, content) '
      'VALUES (new.id, new.content); END',
  'CREATE TRIGGER document_chunks_ad AFTER DELETE ON document_chunks BEGIN '
      'DELETE FROM document_chunks_fts WHERE chunk_id = old.id; END',
  'CREATE TRIGGER document_chunks_au AFTER UPDATE ON document_chunks BEGIN '
      'DELETE FROM document_chunks_fts WHERE chunk_id = old.id; '
      'INSERT INTO document_chunks_fts (chunk_id, content) '
      'VALUES (new.id, new.content); END',
  'CREATE TRIGGER documents_ad AFTER DELETE ON documents BEGIN '
      'DELETE FROM document_chunks WHERE document_id = old.id; END',
  'CREATE TRIGGER sessions_ad AFTER DELETE ON sessions BEGIN '
      'DELETE FROM detected_questions WHERE session_id = old.id; END',
];

/// Une session, deux segments, une question repondue (`q-answered`), une
/// sans reponse (`q-open`), un document indexe.
const List<String> kV2Rows = <String>[
  'INSERT INTO sessions (id, title, created_at, updated_at, duration_seconds, '
      "status) VALUES ('session-1', 'Point client', '2026-11-22T10:00:00.000', "
      "'2026-11-22T10:30:00.000', 1800, 'completed')",
  "INSERT INTO transcript_segments VALUES ('seg-1', 'session-1', 'output', "
      "'Quel est le budget ?', 4000, '2026-11-22T10:00:04.000', "
      "'Intervenant 2')",
  "INSERT INTO transcript_segments VALUES ('seg-2', 'session-1', 'input', "
      "'Je regarde.', 6000, '2026-11-22T10:00:06.000', NULL)",
  'INSERT INTO detected_questions (id, session_id, segment_id, question, '
      'timestamp_ms, answer, answer_model, sources, created_at) VALUES '
      "('q-answered', 'session-1', 'seg-1', 'Quel est le budget ?', 4000, "
      "'40 000 €.', 'claude-haiku-5-5', "
      "'[{\"documentId\":\"budget\",\"title\":\"Budget 2027\","
      "\"excerpt\":\"40 000 euros.\"}]', '2026-11-22T10:00:05.000')",
  'INSERT INTO detected_questions (id, session_id, question, timestamp_ms, '
      "created_at) VALUES ('q-open', 'session-1', 'On livre quand ?', 9000, "
      "'2026-11-22T10:00:09.000')",
  "INSERT INTO documents VALUES ('budget', 'Budget 2027', "
      "'/Users/me/Documents/budget.md', '2026-11-22T09:00:00.000')",
  "INSERT INTO document_chunks VALUES ('budget-0', 'budget', 0, "
      "'Le budget marketing 2027 est fixé à 40 000 euros.')",
];
