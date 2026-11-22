import 'package:core_domain/domain/entities/transcript_segment.entity.dart';
import 'package:core_domain/domain/repositories/transcript.repository.dart';
import 'package:core_foundation/interfaces/future.usecases.dart';

/// Sauvegarde un segment de transcription (remplace celui de meme id).
final class SaveTranscriptSegmentUseCase
    extends
        FutureUseCaseWithParams<
          TranscriptSegmentEntity,
          TranscriptSegmentEntity
        > {
  /// Cree une instance de [SaveTranscriptSegmentUseCase].
  SaveTranscriptSegmentUseCase({
    required TranscriptRepository transcriptRepository,
  }) : _transcriptRepository = transcriptRepository;

  final TranscriptRepository _transcriptRepository;

  @override
  Future<TranscriptSegmentEntity> invoke(TranscriptSegmentEntity params) {
    return _transcriptRepository.save(params);
  }

  /// Retire un segment provisoire dont la phrase finale a ete ecartee.
  ///
  /// Ici et non dans un use case a part : le provisoire et sa phrase finale
  /// passent par le meme port, et [TranscriptionService] ne recoit que ce
  /// use case pour ecrire des segments.
  Future<void> discard(String segmentId) =>
      _transcriptRepository.deleteById(segmentId);
}
