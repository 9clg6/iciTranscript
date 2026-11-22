import 'package:core_domain/domain/entities/transcript_segment.entity.dart';

/// Contrat du repository de segments de transcription.
abstract interface class TranscriptRepository {
  /// Recupere les segments d'une session par son identifiant.
  Future<List<TranscriptSegmentEntity>> getBySessionId(String sessionId);

  /// Sauvegarde un segment de transcription, ou remplace celui de meme id.
  Future<TranscriptSegmentEntity> save(TranscriptSegmentEntity segment);

  /// Sauvegarde un lot de segments de transcription.
  Future<List<TranscriptSegmentEntity>> saveBatch(
    List<TranscriptSegmentEntity> segments,
  );

  /// Supprime un segment par son identifiant.
  Future<void> deleteById(String id);

  /// Supprime tous les segments d'une session.
  Future<void> deleteBySessionId(String sessionId);
}
