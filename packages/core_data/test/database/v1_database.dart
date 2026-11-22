import 'package:drift/drift.dart';
import 'package:drift/native.dart';

/// Base SQLite en memoire au format du schema v1 (tel que livre en v0.2.2),
/// avec des donnees, pour tester la migration 1 -> 2.
///
/// Le DDL est celui que Drift generait pour le schema v1 (sessions,
/// transcript_segments, summaries). `summary-orphan` reference une session
/// supprimee : `DeleteSessionUseCase` supprime les segments puis la session,
/// mais pas le resume, donc ces lignes existent sur les postes des
/// utilisateurs.
///
/// [extraStatements] s'executent apres les donnees, avant de fixer
/// `user_version` a 1 : ils simulent une migration deja (en partie) passee.
QueryExecutor v1DatabaseWithData({
  List<String> extraStatements = const <String>[],
}) {
  return NativeDatabase.memory(
    // ponytail: type `Database` de package:sqlite3, non dependance directe.
    // ignore: always_specify_types
    setup: (raw) {
      raw.execute(
        'CREATE TABLE "sessions" ("id" TEXT NOT NULL, "title" TEXT NOT NULL, '
        '"created_at" TEXT NOT NULL, "updated_at" TEXT NOT NULL, '
        '"duration_seconds" INTEGER NULL, "status" TEXT NOT NULL, '
        'PRIMARY KEY ("id"))',
      );
      raw.execute(
        'CREATE TABLE "transcript_segments" ("id" TEXT NOT NULL, '
        '"session_id" TEXT NOT NULL REFERENCES sessions (id), '
        '"source" TEXT NOT NULL, "text_content" TEXT NOT NULL, '
        '"timestamp_ms" INTEGER NOT NULL, "created_at" TEXT NOT NULL, '
        'PRIMARY KEY ("id"))',
      );
      raw.execute(
        'CREATE TABLE "summaries" ("id" TEXT NOT NULL, '
        '"session_id" TEXT NOT NULL REFERENCES sessions (id), '
        '"content" TEXT NOT NULL, "model" TEXT NOT NULL, '
        '"created_at" TEXT NOT NULL, PRIMARY KEY ("id"))',
      );
      raw.execute(
        "INSERT INTO sessions VALUES ('session-1', 'Point hebdo', "
        "'2026-11-20T09:00:00.000', '2026-11-20T09:45:00.000', 2700, "
        "'completed')",
      );
      raw.execute(
        "INSERT INTO transcript_segments VALUES ('seg-1', 'session-1', "
        "'input', 'Bonjour à tous.', 1000, '2026-11-20T09:00:01.000')",
      );
      raw.execute(
        "INSERT INTO transcript_segments VALUES ('seg-2', 'session-1', "
        "'output', 'On commence par le budget.', 4000, "
        "'2026-11-20T09:00:04.000')",
      );
      raw.execute(
        "INSERT INTO summaries VALUES ('summary-1', 'session-1', "
        "'Budget validé.', 'mistral', '2026-11-20T09:46:00.000')",
      );
      raw.execute(
        "INSERT INTO summaries VALUES ('summary-orphan', 'session-deleted', "
        "'Ancienne réunion.', 'mistral', '2026-10-01T10:00:00.000')",
      );
      extraStatements.forEach(raw.execute);
      raw.execute('PRAGMA user_version = 1');
    },
  );
}
