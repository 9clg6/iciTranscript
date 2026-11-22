import 'package:drift/drift.dart';

import 'package:core_data/database/app_database.dart';

part 'transcript_segment.dao.g.dart';

/// DAO pour les operations sur la table [TranscriptSegments].
@DriftAccessor(tables: <Type>[TranscriptSegments])
class TranscriptSegmentDao extends DatabaseAccessor<AppDatabase>
    with _$TranscriptSegmentDaoMixin {
  /// Cree une instance de [TranscriptSegmentDao].
  TranscriptSegmentDao(super.db);

  /// Recupere les segments d'une session ordonnes par timestamp.
  Future<List<TranscriptSegment>> getBySessionId(String sessionId) {
    return (select(transcriptSegments)
          ..where(($TranscriptSegmentsTable t) => t.sessionId.equals(sessionId))
          ..orderBy(<OrderingTerm Function($TranscriptSegmentsTable)>[
            ($TranscriptSegmentsTable t) => OrderingTerm.asc(t.timestampMs),
          ]))
        .get();
  }

  /// Insere un segment, ou remplace celui de meme id (phrase provisoire).
  Future<void> insertSegment(TranscriptSegmentsCompanion segment) {
    return into(transcriptSegments).insertOnConflictUpdate(segment);
  }

  /// Supprime un segment par son identifiant.
  Future<void> deleteById(String id) {
    return (delete(
      transcriptSegments,
    )..where(($TranscriptSegmentsTable t) => t.id.equals(id))).go();
  }

  /// Insere un lot de segments.
  Future<void> insertBatch(List<TranscriptSegmentsCompanion> segments) {
    return batch((Batch b) => b.insertAll(transcriptSegments, segments));
  }

  /// Supprime tous les segments d'une session.
  Future<void> deleteBySessionId(String sessionId) {
    return (delete(
          transcriptSegments,
        )..where(($TranscriptSegmentsTable t) => t.sessionId.equals(sessionId)))
        .go();
  }

  /// Stream reactif des segments d'une session.
  Stream<List<TranscriptSegment>> watchBySessionId(String sessionId) {
    return (select(transcriptSegments)
          ..where(($TranscriptSegmentsTable t) => t.sessionId.equals(sessionId))
          ..orderBy(<OrderingTerm Function($TranscriptSegmentsTable)>[
            ($TranscriptSegmentsTable t) => OrderingTerm.asc(t.timestampMs),
          ]))
        .watch();
  }
}
