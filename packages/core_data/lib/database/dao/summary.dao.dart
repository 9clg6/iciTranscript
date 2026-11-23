import 'package:drift/drift.dart';

import 'package:core_data/database/app_database.dart';

part 'summary.dao.g.dart';

/// DAO pour les operations sur la table [Summaries].
@DriftAccessor(tables: <Type>[Summaries])
class SummaryDao extends DatabaseAccessor<AppDatabase> with _$SummaryDaoMixin {
  /// Cree une instance de [SummaryDao].
  SummaryDao(super.db);

  /// Recupere le resume d'une session par son identifiant.
  Future<Summary?> getBySessionId(String sessionId) {
    return (select(summaries)
          ..where(($SummariesTable t) => t.sessionId.equals(sessionId)))
        .getSingleOrNull();
  }

  /// Insere ou remplace un resume.
  Future<void> insertSummary(SummariesCompanion summary) {
    return into(summaries).insertOnConflictUpdate(summary);
  }

  /// Supprime le resume d'une session.
  Future<void> deleteBySessionId(String sessionId) {
    return (delete(
      summaries,
    )..where(($SummariesTable t) => t.sessionId.equals(sessionId))).go();
  }
}
