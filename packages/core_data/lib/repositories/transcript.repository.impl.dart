import 'package:core_domain/domain/entities/transcript_segment.entity.dart';
import 'package:core_domain/domain/repositories/transcript.repository.dart';

import 'package:core_data/datasources/local/transcript.local.data_source.dart';
import 'package:core_data/mappers/transcript_segment.mapper.dart';
import 'package:core_data/model/local/transcript_segment.local.model.dart';

/// Implementation de [TranscriptRepository] utilisant la source de donnees locale.
final class TranscriptRepositoryImpl implements TranscriptRepository {
  /// Cree une instance de [TranscriptRepositoryImpl].
  TranscriptRepositoryImpl({
    required TranscriptLocalDataSource transcriptLocalDataSource,
  }) : _localDataSource = transcriptLocalDataSource;

  final TranscriptLocalDataSource _localDataSource;

  @override
  Future<List<TranscriptSegmentEntity>> getBySessionId(String sessionId) async {
    final List<TranscriptSegmentLocalModel> localModels = await _localDataSource
        .getBySessionId(sessionId);
    return localModels
        .map((TranscriptSegmentLocalModel m) => m.toEntity())
        .toList();
  }

  @override
  Future<TranscriptSegmentEntity> save(TranscriptSegmentEntity segment) async {
    final TranscriptSegmentLocalModel localModel = segment.toLocalModel();
    await _localDataSource.insert(localModel);
    return segment;
  }

  @override
  Future<List<TranscriptSegmentEntity>> saveBatch(
    List<TranscriptSegmentEntity> segments,
  ) async {
    final List<TranscriptSegmentLocalModel> localModels = segments
        .map((TranscriptSegmentEntity s) => s.toLocalModel())
        .toList();
    await _localDataSource.insertBatch(localModels);
    return segments;
  }

  @override
  Future<void> deleteById(String id) {
    return _localDataSource.deleteById(id);
  }

  @override
  Future<void> deleteBySessionId(String sessionId) {
    return _localDataSource.deleteBySessionId(sessionId);
  }
}
