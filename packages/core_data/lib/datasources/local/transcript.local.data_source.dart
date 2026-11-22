import 'package:core_data/model/local/transcript_segment.local.model.dart';

/// Contrat de la source de donnees locale pour les segments de transcription.
abstract interface class TranscriptLocalDataSource {
  /// Recupere les segments d'une session.
  Future<List<TranscriptSegmentLocalModel>> getBySessionId(String sessionId);

  /// Insere un segment, ou remplace celui de meme id.
  Future<void> insert(TranscriptSegmentLocalModel segment);

  /// Insere un lot de segments.
  Future<void> insertBatch(List<TranscriptSegmentLocalModel> segments);

  /// Supprime un segment par son identifiant.
  Future<void> deleteById(String id);

  /// Supprime tous les segments d'une session.
  Future<void> deleteBySessionId(String sessionId);

  /// Stream reactif des segments d'une session.
  Stream<List<TranscriptSegmentLocalModel>> watchBySessionId(String sessionId);
}
