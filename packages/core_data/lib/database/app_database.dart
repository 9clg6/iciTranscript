import 'package:drift/drift.dart';

part 'app_database.g.dart';

/// Table des sessions de transcription.
class Sessions extends Table {
  /// Identifiant unique de la session.
  TextColumn get id => text()();

  /// Titre de la session.
  TextColumn get title => text()();

  /// Date de creation au format ISO 8601.
  TextColumn get createdAt => text()();

  /// Date de derniere mise a jour au format ISO 8601.
  TextColumn get updatedAt => text()();

  /// Duree totale en secondes.
  IntColumn get durationSeconds => integer().nullable()();

  /// Statut de la session (active, completed, error).
  TextColumn get status => text()();

  /// Identifiant de l'evenement d'agenda rattache (schema v2).
  TextColumn get calendarEventId => text().nullable()();

  /// Titre de l'evenement d'agenda rattache (schema v2).
  TextColumn get calendarEventTitle => text().nullable()();

  /// Participants, liste JSON de noms (schema v2).
  TextColumn get attendees => text().nullable()();

  /// Audio envoye a la transcription en ligne en temps reel, ms (schema v4).
  IntColumn get cloudRealtimeMs =>
      integer().withDefault(const Constant<int>(0))();

  /// Audio envoye a la transcription en ligne par lot (rattrapage), ms
  /// (schema v4).
  IntColumn get cloudBatchMs => integer().withDefault(const Constant<int>(0))();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};
}

/// Table des segments de transcription.
class TranscriptSegments extends Table {
  /// Identifiant unique du segment.
  TextColumn get id => text()();

  /// Identifiant de la session parente.
  TextColumn get sessionId => text().references(Sessions, #id)();

  /// Source audio (input ou output).
  TextColumn get source => text()();

  /// Texte transcrit.
  TextColumn get textContent => text().named('text_content')();

  /// Offset en millisecondes depuis le debut de la session.
  IntColumn get timestampMs => integer()();

  /// Date de creation au format ISO 8601.
  TextColumn get createdAt => text()();

  /// Locuteur du segment, ex. "Intervenant 2" (schema v2).
  TextColumn get speaker => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};
}

/// Table des resumes de session.
class Summaries extends Table {
  /// Identifiant unique du resume.
  TextColumn get id => text()();

  /// Identifiant de la session parente.
  TextColumn get sessionId => text().references(Sessions, #id)();

  /// Contenu du resume en texte.
  TextColumn get content => text()();

  /// Nom du modele utilise pour generer le resume.
  TextColumn get model => text()();

  /// Date de creation au format ISO 8601.
  TextColumn get createdAt => text()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};
}

/// Table des questions detectees pendant une session, avec leur reponse.
class DetectedQuestions extends Table {
  /// Identifiant unique de la question.
  TextColumn get id => text()();

  /// Identifiant de la session parente (supprimee avec elle, par trigger).
  TextColumn get sessionId => text().references(Sessions, #id)();

  /// Segment d'ou vient la question, s'il est connu.
  TextColumn get segmentId => text().nullable()();

  /// Texte de la question.
  TextColumn get question => text()();

  /// Offset en millisecondes depuis le debut de la session.
  IntColumn get timestampMs => integer()();

  /// Reponse proposee, null tant qu'elle n'est pas generee.
  TextColumn get answer => text().nullable()();

  /// Modele qui a genere la reponse.
  TextColumn get answerModel => text().nullable()();

  /// Sources de la reponse, liste JSON {documentId, title, excerpt}.
  TextColumn get sources => text().nullable()();

  /// Etat : unanswered, answered, shortened, declined, truncated, failed
  /// (schema v3 ; shortened = repondue, texte montre raccourci).
  TextColumn get status =>
      text().withDefault(const Constant<String>('unanswered'))();

  /// Interlocuteur (0, 1, ...) range en texte, null si inconnu (schema v3).
  TextColumn get speaker => text().nullable()();

  /// Source audio : input (l'utilisateur) ou output (schema v3).
  TextColumn get source => text().nullable()();

  /// Date de creation au format ISO 8601.
  TextColumn get createdAt => text()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};
}

/// Table des documents sources ajoutes par l'utilisateur.
class Documents extends Table {
  /// Identifiant unique du document.
  TextColumn get id => text()();

  /// Titre affiche du document.
  TextColumn get title => text()();

  /// Chemin du fichier sur le disque.
  TextColumn get path => text()();

  /// Date d'ajout au format ISO 8601.
  TextColumn get addedAt => text()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};
}

/// Table des morceaux de documents, indexes en plein texte.
class DocumentChunks extends Table {
  /// Identifiant unique du morceau.
  TextColumn get id => text()();

  /// Identifiant du document parent (supprime avec lui, par trigger).
  TextColumn get documentId => text().references(Documents, #id)();

  /// Rang du morceau dans le document, a partir de 0.
  IntColumn get position => integer()();

  /// Texte du morceau.
  TextColumn get content => text()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};
}

/// Index plein texte (FTS5) des morceaux et suppressions en cascade.
///
/// Les cles etrangeres SQLite restent desactivees : les bases v1 gardent des
/// resumes orphelins et `DeleteSessionUseCase` ne supprime pas le resume.
/// Les cascades passent donc par des triggers.
// ponytail: `chunk_id` UNINDEXED, la suppression d'un morceau parcourt
// l'index ; table de correspondance rowid si les documents se comptent
// en milliers.
// ponytail: `INSERT OR REPLACE` sur document_chunks ne declenche pas le
// trigger de suppression (sans `recursive_triggers`) : ligne FTS en double.
// Reecrire un morceau par upsert ou suppression puis insertion.
const List<String> _searchSchema = <String>[
  'CREATE VIRTUAL TABLE IF NOT EXISTS document_chunks_fts USING fts5('
      'chunk_id UNINDEXED, content, '
      "tokenize = 'unicode61 remove_diacritics 2')",
  'CREATE TRIGGER IF NOT EXISTS document_chunks_ai AFTER INSERT ON document_chunks BEGIN '
      'INSERT INTO document_chunks_fts (chunk_id, content) '
      'VALUES (new.id, new.content); END',
  'CREATE TRIGGER IF NOT EXISTS document_chunks_ad AFTER DELETE ON document_chunks BEGIN '
      'DELETE FROM document_chunks_fts WHERE chunk_id = old.id; END',
  'CREATE TRIGGER IF NOT EXISTS document_chunks_au AFTER UPDATE ON document_chunks BEGIN '
      'DELETE FROM document_chunks_fts WHERE chunk_id = old.id; '
      'INSERT INTO document_chunks_fts (chunk_id, content) '
      'VALUES (new.id, new.content); END',
  'CREATE TRIGGER IF NOT EXISTS documents_ad AFTER DELETE ON documents BEGIN '
      'DELETE FROM document_chunks WHERE document_id = old.id; END',
  'CREATE TRIGGER IF NOT EXISTS sessions_ad AFTER DELETE ON sessions BEGIN '
      'DELETE FROM detected_questions WHERE session_id = old.id; END',
];

/// Base de donnees SQLite de l'application via Drift.
@DriftDatabase(
  tables: <Type>[
    Sessions,
    TranscriptSegments,
    Summaries,
    DetectedQuestions,
    Documents,
    DocumentChunks,
  ],
)
class AppDatabase extends _$AppDatabase {
  /// Cree une instance de [AppDatabase].
  AppDatabase(super.e);

  @override
  int get schemaVersion => 4;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (Migrator m) async {
      await m.createAll();
      await _createSearchSchema();
    },
    onUpgrade: (Migrator m, int from, int to) async {
      if (from < 2) {
        // Rejouable : une base peut deja contenir tout ou partie de la v2
        // avec `user_version = 1`.
        await _addColumnIfMissing(m, sessions, sessions.calendarEventId);
        await _addColumnIfMissing(m, sessions, sessions.calendarEventTitle);
        await _addColumnIfMissing(m, sessions, sessions.attendees);
        await _addColumnIfMissing(
          m,
          transcriptSegments,
          transcriptSegments.speaker,
        );
        // `createTable` emet `CREATE TABLE IF NOT EXISTS`.
        await m.createTable(detectedQuestions);
        await m.createTable(documents);
        await m.createTable(documentChunks);
        await _createSearchSchema();
        await customStatement(
          'INSERT INTO document_chunks_fts (chunk_id, content) '
          'SELECT id, content FROM document_chunks WHERE id NOT IN '
          '(SELECT chunk_id FROM document_chunks_fts)',
        );
      }
      if (from < 3) await _migrateDetectedQuestionsToV3(m);
      if (from < 4) {
        // Rejouable, comme la v2.
        await _addColumnIfMissing(m, sessions, sessions.cloudRealtimeMs);
        await _addColumnIfMissing(m, sessions, sessions.cloudBatchMs);
      }
    },
  );

  /// 2 -> 3 : etat, interlocuteur et source des questions detectees.
  /// Rejouable : une base peut deja avoir tout ou partie des colonnes avec
  /// `user_version = 2`. Un etat deja range est garde ; seules les lignes
  /// encore `unanswered` qui ont une reponse passent en `answered`.
  Future<void> _migrateDetectedQuestionsToV3(Migrator m) async {
    await _addColumnIfMissing(m, detectedQuestions, detectedQuestions.status);
    await _addColumnIfMissing(m, detectedQuestions, detectedQuestions.speaker);
    await _addColumnIfMissing(m, detectedQuestions, detectedQuestions.source);
    await customStatement(
      "UPDATE detected_questions SET status = 'answered' "
      "WHERE status = 'unanswered' AND answer IS NOT NULL",
    );
  }

  Future<void> _addColumnIfMissing(
    Migrator m,
    TableInfo<Table, dynamic> table,
    GeneratedColumn<Object> column,
  ) async {
    final List<QueryRow> info = await customSelect(
      'PRAGMA table_info("${table.actualTableName}")',
    ).get();
    if (info.any((QueryRow r) => r.data['name'] == column.name)) return;
    await m.addColumn(table, column);
  }

  Future<void> _createSearchSchema() async {
    for (final String statement in _searchSchema) {
      await customStatement(statement);
    }
  }
}
