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
  'CREATE VIRTUAL TABLE document_chunks_fts USING fts5('
      'chunk_id UNINDEXED, content, '
      "tokenize = 'unicode61 remove_diacritics 2')",
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
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (Migrator m) async {
      await m.createAll();
      await _createSearchSchema();
    },
    onUpgrade: (Migrator m, int from, int to) async {
      if (from < 2) {
        await m.addColumn(sessions, sessions.calendarEventId);
        await m.addColumn(sessions, sessions.calendarEventTitle);
        await m.addColumn(sessions, sessions.attendees);
        await m.addColumn(transcriptSegments, transcriptSegments.speaker);
        await m.createTable(detectedQuestions);
        await m.createTable(documents);
        await m.createTable(documentChunks);
        await _createSearchSchema();
      }
    },
  );

  Future<void> _createSearchSchema() async {
    for (final String statement in _searchSchema) {
      await customStatement(statement);
    }
  }
}
