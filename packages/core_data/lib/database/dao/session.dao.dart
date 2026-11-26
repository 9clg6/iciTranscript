import 'package:drift/drift.dart';

import 'package:core_data/database/app_database.dart';

part 'session.dao.g.dart';

/// DAO pour les operations sur la table [Sessions].
@DriftAccessor(tables: <Type>[Sessions])
class SessionDao extends DatabaseAccessor<AppDatabase> with _$SessionDaoMixin {
  /// Cree une instance de [SessionDao].
  SessionDao(super.db);

  /// Recupere toutes les sessions ordonnees par date de creation decroissante.
  Future<List<Session>> getAll() {
    return (select(sessions)..orderBy(<OrderingTerm Function($SessionsTable)>[
          ($SessionsTable t) => OrderingTerm.desc(t.createdAt),
        ]))
        .get();
  }

  /// Recupere une session par son identifiant.
  Future<Session?> getById(String id) {
    return (select(
      sessions,
    )..where(($SessionsTable t) => t.id.equals(id))).getSingleOrNull();
  }

  /// Insere une nouvelle session.
  Future<void> insertSession(SessionsCompanion session) {
    return into(sessions).insert(session);
  }

  /// Met a jour une session existante.
  Future<void> updateSession(SessionsCompanion session) {
    return (update(sessions)
          ..where(($SessionsTable t) => t.id.equals(session.id.value)))
        .write(session);
  }

  /// Ajoute aux compteurs en ligne (col = col + ?) ; session absente : rien.
  Future<void> addCloudUsage(
    String id, {
    required int realtimeMs,
    required int batchMs,
  }) {
    return customUpdate(
      'UPDATE sessions SET cloud_realtime_ms = cloud_realtime_ms + ?, '
      'cloud_batch_ms = cloud_batch_ms + ? WHERE id = ?',
      variables: <Variable<Object>>[
        Variable<int>(realtimeMs),
        Variable<int>(batchMs),
        Variable<String>(id),
      ],
      updates: <TableInfo<Table, dynamic>>{sessions},
    );
  }

  /// Supprime une session par son identifiant.
  Future<void> deleteById(String id) {
    return (delete(
      sessions,
    )..where(($SessionsTable t) => t.id.equals(id))).go();
  }

  /// Stream reactif de toutes les sessions.
  Stream<List<Session>> watchAll() {
    return (select(sessions)..orderBy(<OrderingTerm Function($SessionsTable)>[
          ($SessionsTable t) => OrderingTerm.desc(t.createdAt),
        ]))
        .watch();
  }
}
