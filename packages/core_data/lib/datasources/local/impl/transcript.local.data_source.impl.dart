import 'package:drift/drift.dart' show Value;
import 'package:core_data/database/app_database.dart';
import 'package:core_data/database/dao/transcript_segment.dao.dart';
import 'package:core_data/datasources/local/transcript.local.data_source.dart';
import 'package:core_data/model/local/transcript_segment.local.model.dart';

/// Implementation de [TranscriptLocalDataSource] utilisant Drift/SQLite.
final class TranscriptLocalDataSourceImpl implements TranscriptLocalDataSource {
  /// Cree une instance de [TranscriptLocalDataSourceImpl].
  TranscriptLocalDataSourceImpl({
    required TranscriptSegmentDao transcriptSegmentDao,
  }) : _transcriptSegmentDao = transcriptSegmentDao;

  final TranscriptSegmentDao _transcriptSegmentDao;

  @override
  Future<List<TranscriptSegmentLocalModel>> getBySessionId(
    String sessionId,
  ) async {
    final List<TranscriptSegment> rows = await _transcriptSegmentDao
        .getBySessionId(sessionId);
    return rows
        .map(
          (TranscriptSegment row) => TranscriptSegmentLocalModel(
            id: row.id,
            sessionId: row.sessionId,
            source: row.source,
            text: row.textContent,
            timestampMs: row.timestampMs,
            createdAt: row.createdAt,
            isPartial: row.isPartial,
          ),
        )
        .toList();
  }

  @override
  Future<void> insert(TranscriptSegmentLocalModel segment) {
    return _transcriptSegmentDao.insertSegment(
      TranscriptSegmentsCompanion.insert(
        id: segment.id,
        sessionId: segment.sessionId,
        source: segment.source,
        textContent: segment.text,
        timestampMs: segment.timestampMs,
        createdAt: segment.createdAt,
        isPartial: Value<bool>(segment.isPartial),
      ),
    );
  }

  @override
  Future<void> insertBatch(List<TranscriptSegmentLocalModel> segments) {
    return _transcriptSegmentDao.insertBatch(
      segments
          .map(
            (TranscriptSegmentLocalModel s) =>
                TranscriptSegmentsCompanion.insert(
                  id: s.id,
                  sessionId: s.sessionId,
                  source: s.source,
                  textContent: s.text,
                  timestampMs: s.timestampMs,
                  createdAt: s.createdAt,
                  isPartial: Value<bool>(s.isPartial),
                ),
          )
          .toList(),
    );
  }

  @override
  Future<void> deleteById(String id) {
    return _transcriptSegmentDao.deleteById(id);
  }

  @override
  Future<void> deleteBySessionId(String sessionId) {
    return _transcriptSegmentDao.deleteBySessionId(sessionId);
  }

  @override
  Stream<List<TranscriptSegmentLocalModel>> watchBySessionId(String sessionId) {
    return _transcriptSegmentDao
        .watchBySessionId(sessionId)
        .map(
          (List<TranscriptSegment> rows) => rows
              .map(
                (TranscriptSegment row) => TranscriptSegmentLocalModel(
                  id: row.id,
                  sessionId: row.sessionId,
                  source: row.source,
                  text: row.textContent,
                  timestampMs: row.timestampMs,
                  createdAt: row.createdAt,
                  isPartial: row.isPartial,
                ),
              )
              .toList(),
        );
  }
}
